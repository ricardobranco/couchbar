import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let output: Data
    public let errorOutput: Data
    public let timedOut: Bool

    public var succeeded: Bool { status == 0 && !timedOut }
    public var stdout: String { String(decoding: output, as: UTF8.self) }
    public var stderr: String { String(decoding: errorOutput, as: UTF8.self) }
}

public enum Shell {
    public static func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval = 10
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try runBlocking(executable, arguments, environment: environment, timeout: timeout)
                })
            }
        }
    }

    private static func runBlocking(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) throws -> ShellResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let exited = Flag()
        let timedOut = Flag()
        process.terminationHandler = { _ in exited.set() }
        try process.run()

        let handle = Unchecked(process)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            guard !exited.isSet else { return }
            timedOut.set()
            handle.value.terminate()
        }

        let errorOutput = Unchecked(Data())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errorOutput.value = collect(errPipe.fileHandleForReading, until: exited)
            group.leave()
        }
        let output = collect(outPipe.fileHandleForReading, until: exited)
        group.wait()
        process.waitUntilExit()

        return ShellResult(
            status: process.terminationStatus,
            output: output,
            errorOutput: errorOutput.value,
            timedOut: timedOut.isSet
        )
    }

    // adb forks its server with our pipes inherited, so EOF may never come: stop reading once the
    // process has exited and the pipe is drained instead of waiting for EOF.
    private static func collect(_ handle: FileHandle, until exited: Flag) -> Data {
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        while true {
            if poll(&descriptor, 1, 50) > 0 {
                let count = read(fd, &buffer, buffer.count)
                if count > 0 {
                    data.append(buffer, count: count)
                    continue
                }
                if count == 0 || (errno != EAGAIN && errno != EINTR) { break }
            } else if exited.isSet {
                break
            }
        }
        return data
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

final class Unchecked<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
