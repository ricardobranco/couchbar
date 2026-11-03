import AppKit
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

    init() {
        // scrcpy is a separate process and would outlive the app, leaving a mirror window nothing controls.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let process = self?.process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

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

    // scrcpy's SDL loop only notices SIGTERM on its next window event, so an idle mirror window can
    // ignore it indefinitely; it gets a moment to exit cleanly and is then killed.
    func stop() {
        guard let process else { return }
        process.terminate()
        Task {
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func bringToFront() {
        guard let process else { return }
        NSRunningApplication(processIdentifier: process.processIdentifier)?.activate()
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
