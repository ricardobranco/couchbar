import Foundation
import ImageIO

public struct AppArtwork: Codable, Sendable, Equatable {
    public var label: String
    public var imageFile: String?
    public var isBanner: Bool
    var apkPath: String
}

/// Reads each app's own label and Android TV banner (or icon) out of its APK on the TV. Only the
/// manifest, the resource table and the one image are copied, then cached until the app updates.
public struct AppArtworkLoader: Sendable {
    let adb: ADB
    let serial: String
    let aapt2: URL
    public let cacheDirectory: URL

    public init?(adb: ADB, serial: String, cacheDirectory: URL) {
        guard let aapt2 = Self.locateAAPT2(near: adb) else { return nil }
        self.adb = adb
        self.serial = serial
        self.aapt2 = aapt2
        self.cacheDirectory = cacheDirectory
    }

    public func load(_ packages: [String], update: @Sendable (String, AppArtwork) async -> Void) async {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        guard let paths = try? await apkPaths() else { return }
        for package in packages {
            guard let apkPath = paths[package] else { continue }
            if let cached = cached(package), cached.apkPath == apkPath {
                await update(package, cached)
            } else if let artwork = try? await extract(package, apkPath: apkPath) {
                if let data = try? JSONEncoder().encode(artwork) {
                    try? data.write(to: metadataURL(package))
                }
                await update(package, artwork)
            }
        }
    }

    private func cached(_ package: String) -> AppArtwork? {
        (try? Data(contentsOf: metadataURL(package))).flatMap { try? JSONDecoder().decode(AppArtwork.self, from: $0) }
    }

    private func metadataURL(_ package: String) -> URL {
        cacheDirectory.appending(path: "\(package).json")
    }

    private func apkPaths() async throws -> [String: String] {
        let output = try await shell("pm list packages -f")
        var paths: [String: String] = [:]
        for match in output.matches(of: /package:(\S+\.apk)=([\w.]+)/) {
            paths[String(match.2)] = String(match.1)
        }
        return paths
    }

    private func extract(_ package: String, apkPath: String) async throws -> AppArtwork {
        let work = FileManager.default.temporaryDirectory.appending(path: "couchbar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        for entry in ["AndroidManifest.xml", "resources.arsc"] {
            try await pull(apkPath, entry: entry).write(to: work.appending(path: entry))
        }
        let apk = work.appending(path: "resources.apk")
        let zip = try await Shell.run(URL(fileURLWithPath: "/usr/bin/zip"), ["-q", "-0", "-j", apk.path,
            work.appending(path: "AndroidManifest.xml").path, work.appending(path: "resources.arsc").path])
        guard zip.succeeded else { throw ADBError.commandFailed("zip failed") }
        let badging = try await Shell.run(aapt2, ["dump", "badging", apk.path], timeout: 30).stdout
        guard let badge = Badging.parse(badging) else { throw ADBError.commandFailed("No application in \(package)") }

        var artwork = AppArtwork(label: badge.label, imageFile: nil, isBanner: false, apkPath: apkPath)
        let candidates = [(badge.banner, true), (badge.largestIcon, false)]
        for case let (path?, isBanner) in candidates where !path.hasSuffix(".xml") {
            let best = try await largestVariant(of: path, in: apkPath)
            let data = try await pull(apkPath, entry: best)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { continue }
            let file = "\(package).\((best as NSString).pathExtension)"
            try data.write(to: cacheDirectory.appending(path: file))
            artwork.imageFile = file
            artwork.isBanner = isBanner
            break
        }
        return artwork
    }

    /// The manifest points at one density; the same file name in a higher density folder looks sharper.
    private func largestVariant(of path: String, in apkPath: String) async throws -> String {
        let name = (path as NSString).lastPathComponent
        let folder = (path as NSString).deletingLastPathComponent
        guard let type = folder.split(separator: "/").last?.split(separator: "-").first else { return path }
        let listing = try await shell("unzip -l \(apkPath.shellQuoted) | grep \("/\(name)".shellQuoted) || true")
        let variants = listing.matches(of: /^\s*(\d+)\s+\S+\s+\S+\s+(res\/(\w+)[^\s]*)$/.anchorsMatchLineEndings())
            .filter { $0.3 == type && ($0.2 as Substring).hasSuffix("/\(name)") }
        return variants.max { (Int($0.1) ?? 0) < (Int($1.1) ?? 0) }.map { String($0.2) } ?? path
    }

    private func pull(_ apkPath: String, entry: String) async throws -> Data {
        let result = try await adb.run(["-s", serial, "exec-out", "unzip -p \(apkPath.shellQuoted) \(entry.shellQuoted)"], timeout: 30)
        guard result.succeeded, !result.output.isEmpty else { throw ADBError.commandFailed("Could not read \(entry)") }
        return result.output
    }

    private func shell(_ command: String) async throws -> String {
        try await TVClient(adb: adb, serial: serial).shell(command, timeout: 20)
    }

    static func locateAAPT2(near adb: ADB) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let sdks = [
            adb.executable.deletingLastPathComponent().deletingLastPathComponent().path,
            environment["ANDROID_HOME"],
            environment["ANDROID_SDK_ROOT"],
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Android/sdk").path,
        ].compactMap { $0 }
        for sdk in sdks {
            let buildTools = URL(fileURLWithPath: sdk).appending(path: "build-tools")
            let versions = (try? FileManager.default.contentsOfDirectory(atPath: buildTools.path)) ?? []
            for version in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
                let aapt2 = buildTools.appending(path: "\(version)/aapt2")
                if FileManager.default.isExecutableFile(atPath: aapt2.path) { return aapt2 }
            }
        }
        return nil
    }
}

struct Badging: Equatable {
    var label: String
    var banner: String?
    var largestIcon: String?

    static func parse(_ output: String) -> Badging? {
        guard let application = output.firstMatch(of: /^application: label='([^']*)' icon='([^']*)'(?: banner='([^']*)')?/.anchorsMatchLineEndings()) else { return nil }
        let icons = output.matches(of: /^application-icon-(\d+):'([^']+)'/.anchorsMatchLineEndings())
        let largest = icons.filter { $0.1 != "65534" }.max { (Int($0.1) ?? 0) < (Int($1.1) ?? 0) }.map { String($0.2) }
        let icon = String(application.2)
        return Badging(
            label: String(application.1),
            banner: application.3.map(String.init),
            largestIcon: largest ?? (icon.isEmpty ? nil : icon)
        )
    }
}
