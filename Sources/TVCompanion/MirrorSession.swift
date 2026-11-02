import Foundation
import Observation
import TVCompanionCore

@Observable
@MainActor
final class MirrorSession {
    private(set) var isRunning = false
    private(set) var lastError: String?
    private var process: Process?

    static let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/TV Companion/scrcpy.log")

    func start(scrcpy: URL, adb: ADB, serial: String, title: String, options: MirrorOptions) {
        guard process == nil else { return }
        lastError = nil

        let process = Process()
        process.executableURL = scrcpy
        process.arguments = Scrcpy.arguments(serial: serial, title: title, options: options)
        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = adb.executable.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        do {
            try FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: Self.logURL)
            process.standardOutput = log
            process.standardError = log
            process.terminationHandler = { [weak self] finished in
                try? log.close()
                let status = finished.terminationStatus
                let reason = finished.terminationReason
                Task { @MainActor in self?.finished(status: status, reason: reason) }
            }
            try process.run()
            self.process = process
            isRunning = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    #if DEBUG
    func simulateRunning() {
        isRunning = true
    }
    #endif

    func stop() {
        process?.terminate()
    }

    private func finished(status: Int32, reason: Process.TerminationReason) {
        process = nil
        isRunning = false
        guard status != 0, reason == .exit else { return }
        let log = (try? String(contentsOf: Self.logURL, encoding: .utf8)) ?? ""
        let errorLine = log.split(separator: "\n").last { $0.hasPrefix("ERROR") }
        lastError = errorLine.map(String.init) ?? "scrcpy exited with status \(status)."
    }
}
