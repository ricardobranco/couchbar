import Foundation

public struct MirrorOptions: Sendable, Equatable {
    public var maxSize: Int = 1920
    public var bitRateMbps: Int = 8
    public var maxFPS: Int = 60
    public var forwardAudio: Bool = false
    public var allowControl: Bool = true
    public var alwaysOnTop: Bool = false

    public init() {}
}

public enum Scrcpy {
    public static func locate(override: String? = nil) -> URL? {
        [override, "/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy"]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    public static func arguments(serial: String, title: String, options: MirrorOptions) -> [String] {
        var arguments = [
            "--serial=\(serial)",
            "--window-title=\(title)",
            "--max-size=\(options.maxSize)",
            "--video-bit-rate=\(options.bitRateMbps)M",
            "--max-fps=\(options.maxFPS)",
            "--no-power-on",
        ]
        // Playback capture with --audio-dup keeps the sound on the TV (and its soundbar) too.
        arguments += options.forwardAudio ? ["--audio-source=playback", "--audio-dup"] : ["--no-audio"]
        if !options.allowControl { arguments.append("--no-control") }
        if options.alwaysOnTop { arguments.append("--always-on-top") }
        return arguments
    }
}
