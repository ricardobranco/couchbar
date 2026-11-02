import Foundation

public enum ADBError: LocalizedError {
    case notFound
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: "adb was not found. Install Android platform-tools or set its path in Settings."
        case .commandFailed(let message): message
        }
    }
}

public struct ADB: Sendable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    public static func locate(override: String? = nil) -> ADB? {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            override,
            env["ADB"],
            env["ANDROID_HOME"].map { "\($0)/platform-tools/adb" },
            env["ANDROID_SDK_ROOT"].map { "\($0)/platform-tools/adb" },
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
            .map { ADB(executable: URL(fileURLWithPath: $0)) }
    }

    public func run(_ arguments: [String], timeout: TimeInterval = 10) async throws -> ShellResult {
        try await Shell.run(executable, arguments, timeout: timeout)
    }

    public func devices() async throws -> [ADBDevice] {
        ADBDevice.parse(try await run(["devices", "-l"]).stdout)
    }

    public func mdnsServices() async throws -> [MDNSService] {
        MDNSService.parse(try await run(["mdns", "services"]).stdout)
    }

    @discardableResult
    public func connect(_ address: String) async throws -> Bool {
        let output = try await run(["connect", address], timeout: 8).stdout
        return output.contains("connected to")
    }
}

public struct ADBDevice: Sendable, Hashable, Identifiable {
    public let serial: String
    public let state: String
    public let model: String?

    public var id: String { serial }
    public var isOnline: Bool { state == "device" }

    public static func parse(_ output: String) -> [ADBDevice] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 2 else { return nil }
            let model = fields.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)) }
            return ADBDevice(serial: fields[0], state: fields[1], model: model)
        }
    }
}

public struct MDNSService: Sendable, Hashable {
    public let name: String
    public let type: String
    public let address: String

    public var isTLS: Bool { type.hasPrefix("_adb-tls-connect") }

    public static func parse(_ output: String) -> [MDNSService] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count == 3, fields[1].hasPrefix("_adb") else { return nil }
            return MDNSService(name: fields[0], type: fields[1], address: fields[2])
        }
    }
}
