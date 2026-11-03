import Foundation

public enum WakeOnLAN {
    public static func send(to macAddress: String) throws {
        let bytes = macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { throw ADBError.commandFailed("Invalid MAC address \(macAddress)") }
        let packet = [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: bytes, count: 16).joined())

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { throw ADBError.commandFailed("Could not open a UDP socket.") }
        defer { close(sock) }
        var enable: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9).bigEndian
        address.sin_addr.s_addr = INADDR_BROADCAST
        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(sock, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw ADBError.commandFailed("Could not send the wake packet.") }
    }
}
