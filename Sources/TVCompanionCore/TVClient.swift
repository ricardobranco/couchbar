import Foundation

public struct TVStatus: Sendable, Equatable {
    public var power: PowerState?
    public var volume: VolumeLevel?
    public var foregroundPackage: String?
    public var nowPlaying: NowPlaying?

    public init(power: PowerState? = nil, volume: VolumeLevel? = nil, foregroundPackage: String? = nil, nowPlaying: NowPlaying? = nil) {
        self.power = power
        self.volume = volume
        self.foregroundPackage = foregroundPackage
        self.nowPlaying = nowPlaying
    }
}

public struct TVInfo: Sendable, Equatable {
    public var name: String
    public var serialNumber: String
    public var macAddress: String?
    public var inputs: [TVInput]
    public var apps: [TVApp]

    public init(name: String, serialNumber: String, macAddress: String?, inputs: [TVInput], apps: [TVApp]) {
        self.name = name
        self.serialNumber = serialNumber
        self.macAddress = macAddress
        self.inputs = inputs
        self.apps = apps
    }
}

public struct TVClient: Sendable {
    public let adb: ADB
    public let serial: String

    public init(adb: ADB, serial: String) {
        self.adb = adb
        self.serial = serial
    }

    @discardableResult
    public func shell(_ command: String, timeout: TimeInterval = 10) async throws -> String {
        let result = try await adb.run(["-s", serial, "shell", command], timeout: timeout)
        guard result.succeeded else {
            let message = result.timedOut ? "The TV did not answer in time." : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ADBError.commandFailed(message.isEmpty ? "adb exited with \(result.status)" : message)
        }
        return result.stdout
    }

    private static let separator = "@@TVCOMPANION@@"

    public func info() async throws -> TVInfo {
        let sections = try await shell([
            "settings get global device_name",
            "getprop ro.serialno",
            "ip -o link",
            "dumpsys tv_input",
            "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER",
        ].joined(separator: "; echo \(Self.separator); "), timeout: 15)
            .components(separatedBy: Self.separator)
        guard sections.count == 5 else { throw ADBError.commandFailed("Unexpected answer from the TV.") }

        let name = sections[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let packages = Set(sections[4].matches(of: /^\s*([\w.]+)\//.anchorsMatchLineEndings()).map { String($0.1) })
        return TVInfo(
            name: name.isEmpty || name == "null" ? "TV" : name,
            serialNumber: sections[1].trimmingCharacters(in: .whitespacesAndNewlines),
            macAddress: MACAddress.parse(sections[2]),
            inputs: TVInput.parse(sections[3]),
            apps: packages.filter(TVApp.isUserFacing).map(TVApp.init).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
    }

    public func status() async throws -> TVStatus {
        let sections = try await shell([
            "dumpsys power | grep mWakefulness=",
            "cmd media_session volume --stream 3 --get",
            "dumpsys window | grep mCurrentFocus=",
            "dumpsys media_session",
        ].joined(separator: "; echo \(Self.separator); "))
            .components(separatedBy: Self.separator)
        guard sections.count == 4 else { throw ADBError.commandFailed("Unexpected answer from the TV.") }

        return TVStatus(
            power: PowerState.parse(sections[0]),
            volume: VolumeLevel.parse(sections[1]),
            foregroundPackage: ForegroundApp.parse(sections[2]),
            nowPlaying: NowPlaying.parse(sections[3])
        )
    }

    public func press(_ keys: [TVKey]) async throws {
        guard !keys.isEmpty else { return }
        try await shell("input keyevent " + keys.map { String($0.rawValue) }.joined(separator: " "))
    }

    public func press(_ key: TVKey) async throws {
        try await press([key])
    }

    // Steps with key presses instead of `media_session volume --set`: with an ARC soundbar the keys
    // go out over CEC, while --set only changes the TV's own level.
    public func stepVolume(by delta: Int) async throws {
        try await press(Array(repeating: delta > 0 ? .volumeUp : .volumeDown, count: abs(delta)))
    }

    public func launch(_ package: String) async throws {
        try await shell("monkey -p \(package.shellQuoted) -c android.intent.category.LEANBACK_LAUNCHER 1")
    }

    public func switchInput(_ input: TVInput) async throws {
        if case .tuner = input.kind {
            try await press(.tv)
            return
        }
        let encodedID = input.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "._-"))) ?? input.id
        // TCL's TVActivity only matches on the MIME type, so it is passed explicitly.
        let output = try await shell("am start -a android.intent.action.VIEW -t vnd.android.cursor.item/channel -d content://android.media.tv/passthrough/\(encodedID)")
        if output.contains("Error") { throw ADBError.commandFailed(output) }
    }

    public func sendText(_ text: String) async throws {
        let escaped = text.replacingOccurrences(of: " ", with: "%s")
        try await shell("input text \(escaped.shellQuoted)")
    }

    public func screenshot() async throws -> Data {
        let result = try await adb.run(["-s", serial, "exec-out", "screencap", "-p"], timeout: 15)
        guard result.succeeded, !result.output.isEmpty else { throw ADBError.commandFailed("Could not take a screenshot.") }
        return result.output
    }
}

extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
