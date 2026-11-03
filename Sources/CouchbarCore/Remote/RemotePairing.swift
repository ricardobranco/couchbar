import Foundation

/// Pairs with the TV's Android TV Remote Service (port 6467), the same way the Google Home app does:
/// the TV shows a six-character code that is typed in on this Mac.
@MainActor
public final class RemotePairing {
    private let connection: FramedConnection
    private let identity: RemoteIdentity
    private let clientName: String

    public init(host: String, identity: RemoteIdentity, clientName: String) {
        connection = FramedConnection(host: host, port: 6467, identity: identity)
        self.identity = identity
        self.clientName = clientName
    }

    /// Returns once the TV shows the code.
    public func start() async throws {
        try await connection.open()
        send { request in
            request.message(10) {
                $0.string(1, "atvremote")
                $0.string(2, self.clientName)
            }
        }
        while true {
            let reply = try await nextReply()
            if reply.has(11) {
                send { options in
                    options.message(20) {
                        $0.message(1, Self.hexEncoding)
                        $0.varint(3, Self.inputRole)
                    }
                }
            } else if reply.has(20) {
                send { configuration in
                    configuration.message(30) {
                        $0.message(1, Self.hexEncoding)
                        $0.varint(2, Self.inputRole)
                    }
                }
            } else if reply.has(31) {
                return
            }
        }
    }

    public func finish(code: String) async throws {
        guard let serverCertificate = connection.serverCertificate else { throw RemoteError.connectionClosed }
        let secret = try PairingSecret.make(code: code.uppercased(), client: identity.certificate, server: serverCertificate)
        send { $0.message(40) { $0.bytes(1, secret) } }
        while try await !nextReply().has(41) {}
        connection.close()
    }

    public func cancel() {
        connection.close()
    }

    private static let inputRole = 1
    private static func hexEncoding(_ encoding: inout ProtoWriter) {
        encoding.varint(1, 3)
        encoding.varint(2, 6)
    }

    private func send(_ build: (inout ProtoWriter) -> Void) {
        var message = ProtoWriter()
        message.varint(1, 2)
        message.varint(2, 200)
        build(&message)
        connection.send(message.data)
    }

    private func nextReply() async throws -> ProtoMessage {
        let reply = try ProtoMessage(try await connection.next())
        if let status = reply.int(2), status != 200 {
            connection.close()
            throw status == 402 ? RemoteError.invalidCode : RemoteError.rejected(status)
        }
        return reply
    }
}
