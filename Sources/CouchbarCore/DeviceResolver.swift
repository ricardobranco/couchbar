import Foundation

public struct DeviceResolver: Sendable {
    public let adb: ADB

    public init(adb: ADB) {
        self.adb = adb
    }

    /// Finds the TV among connected adb devices, connecting through mDNS or a manual address when needed.
    /// `serialNumber` is the TV's `ro.serialno`, which stays stable while its wireless debugging port changes.
    public func resolve(serialNumber: String?, manualAddress: String?) async throws -> String? {
        if let manualAddress, !manualAddress.isEmpty {
            let address = manualAddress.contains(":") ? manualAddress : "\(manualAddress):5555"
            try await adb.connect(address)
        }
        if let serial = try await findConnected(serialNumber: serialNumber) {
            return serial
        }

        let services = try await adb.mdnsServices()
            .filter { serialNumber == nil || $0.name.contains(serialNumber!) }
            .sorted { $0.isTLS && !$1.isTLS }
        for service in services {
            guard try await adb.connect(service.address) else { continue }
            if let serial = try await findConnected(serialNumber: serialNumber) {
                return serial
            }
        }
        return nil
    }

    private func findConnected(serialNumber: String?) async throws -> String? {
        let online = try await adb.devices().filter(\.isOnline)
        if let serialNumber, let match = online.first(where: { $0.serial.contains(serialNumber) }) {
            return match.serial
        }
        for device in online {
            let props = try await adb.run(["-s", device.serial, "shell", "getprop ro.build.characteristics; getprop ro.serialno"], timeout: 5).stdout
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard props.count >= 2, props[0].split(separator: ",").contains("tv") else { continue }
            if serialNumber == nil || props[1] == serialNumber {
                return device.serial
            }
        }
        return nil
    }
}
