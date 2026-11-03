import Foundation
import Testing
@testable import CouchbarCore

// Read-only checks against a real TV on the network: `TV_LIVE_TESTS=1 swift test --filter LiveTVTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TV_LIVE_TESTS"] == "1"))
struct LiveTVTests {
    @Test func readsInfoAndStatus() async throws {
        let adb = try #require(ADB.locate())
        let serial = try #require(try await DeviceResolver(adb: adb).resolve(serialNumber: nil, manualAddress: nil))
        let client = TVClient(adb: adb, serial: serial)

        let info = try await client.info()
        #expect(!info.serialNumber.isEmpty)
        #expect(!info.inputs.isEmpty)
        #expect(!info.apps.isEmpty)

        let status = try await client.status()
        #expect(status.power != nil)
        #expect(status.volume != nil)
        print("TV:", info.name, info.serialNumber, info.macAddress ?? "-")
        print("Inputs:", info.inputs.map(\.defaultName))
        print("Apps:", info.apps.map(\.name))
        print("Status:", status)
    }

    @Test func readsAppArtwork() async throws {
        let adb = try #require(ADB.locate())
        let serial = try #require(try await DeviceResolver(adb: adb).resolve(serialNumber: nil, manualAddress: nil))
        let directory = FileManager.default.temporaryDirectory.appending(path: "couchbar-artwork-test")
        try? FileManager.default.removeItem(at: directory)
        let packages = ProcessInfo.processInfo.environment["TV_ARTWORK_PACKAGES"]?.split(separator: ",").map(String.init)
            ?? ["com.netflix.ninja", "com.spotify.tv.android"]
        let loader = try #require(AppArtworkLoader(adb: adb, serial: serial, cacheDirectory: directory))
        let found = Found()
        await loader.load(packages) { await found.add($0, $1) }
        let artwork = await found.all
        print("Artwork:", artwork)
        #expect(artwork["com.netflix.ninja"]?.label == "Netflix")
        #expect(artwork["com.netflix.ninja"]?.isBanner == true)
        #expect(artwork["com.spotify.tv.android"]?.label == "Spotify")
    }
}

private actor Found {
    var all: [String: AppArtwork] = [:]
    func add(_ package: String, _ artwork: AppArtwork) { all[package] = artwork }
}
