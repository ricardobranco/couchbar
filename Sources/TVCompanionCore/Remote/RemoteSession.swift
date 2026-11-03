import Foundation

/// A paired connection to the TV's Android TV Remote Service (port 6466). Its keyboard follows the
/// text field focused on the TV, as in the Google Home app.
@MainActor
public final class RemoteSession {
    public struct TextField: Equatable, Sendable {
        public var label: String
        public var value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public var onTextField: ((TextField?) -> Void)?
    public private(set) var textField: TextField? {
        didSet { if textField != oldValue { onTextField?(textField) } }
    }
    public var onClose: (() -> Void)?

    private let connection: FramedConnection
    private var imeCounter = 0
    private var fieldCounter = 0
    private var tvText = ""
    private var pendingText: String?
    private var editInFlight = 0

    public static let enterKey = 66
    private static let deleteKey = 67

    // Ping, keys, IME, power, volume and app links.
    private static let features = 0b10_0110_0111

    public init(host: String, identity: RemoteIdentity) {
        connection = FramedConnection(host: host, port: 6466, identity: identity)
    }

    public func connect() async throws {
        connection.onClose = { [weak self] in self?.onClose?() }
        try await connection.open()
        // An unpaired client is dropped right after the TLS handshake, before the TV configures it.
        let first = try ProtoMessage(try await connection.next(timeout: .seconds(5)))
        connection.onMessage = { [weak self] in self?.handle($0) }
        handle(message: first)
    }

    public func close() {
        connection.close()
    }

    /// Edits the focused text field to read `text`, like typing on the Google Home keyboard. The TV
    /// only inserts at the cursor, so removed characters go out as delete key presses.
    public func setText(_ text: String) {
        guard var field = textField else { return }
        field.value = text
        textField = field
        pendingText = text
        sendNextEdit()
    }

    // The TV drops an edit whose counters don't match its field's current state, and only reports the
    // new counters in the echo of the previous edit, so edits go out one at a time.
    private func sendNextEdit() {
        guard editInFlight == 0, let pendingText else { return }
        guard pendingText != tvText else {
            self.pendingText = nil
            return
        }
        let common = zip(tvText, pendingText).prefix { $0 == $1 }.count
        if tvText.count > common {
            press(Self.deleteKey)
        } else {
            insert(String(pendingText.dropFirst(common)))
        }
        editInFlight += 1
        let edit = editInFlight
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard editInFlight == edit else { return }
            editInFlight = 0
            self.pendingText = nil
            textField?.value = tvText
        }
    }

    private func insert(_ text: String) {
        let cursor = text.utf16.count - 1
        send { message in
            message.message(21) {
                $0.varint(1, self.imeCounter)
                $0.varint(2, self.fieldCounter)
                $0.message(3) { edit in
                    edit.varint(1, 1)
                    edit.message(2) {
                        $0.varint(1, cursor)
                        $0.varint(2, cursor)
                        $0.string(3, text)
                    }
                }
            }
        }
    }

    public func press(_ keyCode: Int) {
        send { message in
            message.message(10) {
                $0.varint(1, keyCode)
                $0.varint(2, 3)
            }
        }
    }

    private func send(_ build: (inout ProtoWriter) -> Void) {
        var message = ProtoWriter()
        build(&message)
        connection.send(message.data)
    }

    private func handle(_ data: Data) {
        guard let message = try? ProtoMessage(data) else { return }
        handle(message: message)
    }

    private func handle(message: ProtoMessage) {
        if message.has(1) {
            let supported = message.message(1)?.int(1) ?? 0
            send { reply in
                reply.message(1) {
                    $0.varint(1, Self.features & supported)
                    $0.message(2) {
                        $0.varint(3, 1)
                        $0.string(4, "1")
                        $0.string(5, "atvremote")
                        $0.string(6, "1.0.0")
                    }
                }
            }
        } else if message.has(2) {
            send { reply in reply.message(2) { $0.varint(1, Self.features) } }
        } else if let ping = message.message(8) {
            send { reply in reply.message(9) { $0.varint(1, ping.int(1) ?? 0) } }
        } else if let inject = message.message(20) {
            // Sent whenever focus moves: with a text field's state, or without one when it left a field.
            imeCounter = inject.message(1)?.int(1) ?? imeCounter
            pendingText = nil
            editInFlight = 0
            if let status = inject.message(2) {
                update(from: status)
                textField = Self.textField(status)
            } else {
                textField = nil
            }
        } else if let show = message.message(22), let status = show.message(2) {
            update(from: status)
            editInFlight = 0
            if pendingText == nil {
                textField = Self.textField(status)
            } else {
                sendNextEdit()
            }
        }
    }

    private func update(from status: ProtoMessage) {
        fieldCounter = status.int(1) ?? fieldCounter
        tvText = status.string(2) ?? ""
    }

    private static func textField(_ status: ProtoMessage) -> TextField {
        TextField(label: status.string(6) ?? "", value: status.string(2) ?? "")
    }
}
