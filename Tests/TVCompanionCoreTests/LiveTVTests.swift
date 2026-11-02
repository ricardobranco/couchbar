import Foundation
import Testing
@testable import TVCompanionCore

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
}
