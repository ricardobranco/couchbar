import Foundation

public enum TVKey: Int, Sendable {
    case home = 3
    case back = 4
    case up = 19
    case down = 20
    case left = 21
    case right = 22
    case center = 23
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case delete = 67
    case menu = 82
    case playPause = 85
    case next = 87
    case previous = 88
    case volumeMute = 164
    case channelUp = 166
    case channelDown = 167
    case tv = 170
    case settings = 176
    case sleep = 223
    case wakeUp = 224
}

public struct VolumeLevel: Sendable, Equatable {
    public let current: Int
    public let range: ClosedRange<Int>

    public init(current: Int, range: ClosedRange<Int>) {
        self.current = current
        self.range = range
    }

    // "[V] volume is 15 in range [0..100]"
    public static func parse(_ output: String) -> VolumeLevel? {
        guard let match = output.firstMatch(of: /volume is (\d+) in range \[(\d+)\.\.(\d+)\]/),
              let current = Int(match.1), let low = Int(match.2), let high = Int(match.3), low <= high
        else { return nil }
        return VolumeLevel(current: current, range: low...high)
    }
}

public enum PowerState: String, Sendable {
    case awake = "Awake"
    case asleep = "Asleep"
    case dozing = "Dozing"
    case dreaming = "Dreaming"

    public var isOn: Bool { self == .awake || self == .dreaming }

    public static func parse(_ output: String) -> PowerState? {
        output.firstMatch(of: /mWakefulness=(\w+)/).flatMap { PowerState(rawValue: String($0.1)) }
    }
}

public enum ForegroundApp {
    // "mCurrentFocus=Window{9094d63 u0 com.tcl.tv/com.tcl.tv.TVActivity}"
    public static func parse(_ output: String) -> String? {
        output.firstMatch(of: /mCurrentFocus=Window\{\S+ \S+ ([\w.]+)\//).map { String($0.1) }
    }
}

public struct TVInput: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case hdmi(port: Int)
        case tuner
    }

    public enum State: Int, Sendable {
        case connected = 0
        case standby = 1
        case disconnected = 2
    }

    public let id: String
    public let kind: Kind
    public let state: State

    public init(id: String, kind: Kind, state: State) {
        self.id = id
        self.kind = kind
        self.state = state
    }

    public var defaultName: String {
        switch kind {
        case .hdmi(let port): "HDMI \(port)"
        case .tuner: "Live TV"
        }
    }

    public var sortKey: Int {
        switch kind {
        case .tuner: 0
        case .hdmi(let port): port
        }
    }

    public static func parse(_ dump: String) -> [TVInput] {
        var hdmiPorts: [String: Int] = [:]
        for match in dump.matches(of: /TvInputHardwareInfo \{id=(\d+),[^}]*hdmi_port=(\d+)/) {
            if let port = Int(match.2) { hdmiPorts[String(match.1)] = port }
        }

        var inputs: [String: TVInput] = [:]
        for match in dump.matches(of: /^\s+(\S+\/\.(\w+)\/HW(\d+)): info: TvInputInfo\{[^}]*\}; state: (\d)/.anchorsMatchLineEndings()) {
            let id = String(match.1)
            let state = Int(match.4).flatMap(State.init(rawValue:)) ?? .disconnected
            if match.2.contains("Tuner") {
                inputs[id] = TVInput(id: id, kind: .tuner, state: state)
            } else if let port = hdmiPorts[String(match.3)] {
                inputs[id] = TVInput(id: id, kind: .hdmi(port: port), state: state)
            }
        }
        return inputs.values.sorted { $0.sortKey < $1.sortKey }
    }
}

public struct NowPlaying: Sendable, Equatable {
    public let package: String
    public let title: String
    public let artist: String?
    public let isPlaying: Bool

    public init(package: String, title: String, artist: String?, isPlaying: Bool) {
        self.package = package
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
    }

    public static func parse(_ dump: String) -> NowPlaying? {
        let stack = dump.components(separatedBy: "Sessions Stack").dropFirst().first ?? ""
        let sessions = stack.components(separatedBy: "\n      package=").dropFirst()
        let parsed = sessions.compactMap(parseSession)
        return parsed.first { $0.isPlaying } ?? parsed.first
    }

    private static func parseSession(_ block: String) -> NowPlaying? {
        let package = String(block.prefix { !$0.isNewline })
        guard let state = block.firstMatch(of: /state=PlaybackState \{state=(\w+)\(/)?.1,
              state == "PLAYING" || state == "PAUSED" || state == "BUFFERING",
              let description = block.firstMatch(of: /metadata: size=\d+, description=(.*)/)?.1
        else { return nil }

        var parts = description.components(separatedBy: ", ")
        if parts.last == "null" { parts.removeLast() }
        guard let title = parts.first, !title.isEmpty, title != "null" else { return nil }
        let artist = parts.dropFirst().joined(separator: ", ")
        return NowPlaying(
            package: package,
            title: title,
            artist: artist.isEmpty || artist == "null" ? nil : artist,
            isPlaying: state != "PAUSED"
        )
    }
}

public enum MACAddress {
    // `ip -o link`: prefers the interface that is up, so a Wi-Fi TV doesn't get its idle Ethernet MAC.
    public static func parse(_ output: String) -> String? {
        let links = output.matches(of: /\d+: (eth0|wlan0): <([^>]*)>.*?link\/ether ([0-9a-f:]{17})/)
        let up = links.first { $0.2.split(separator: ",").contains("LOWER_UP") }
        return (up ?? links.first).map { String($0.3) }
    }
}
