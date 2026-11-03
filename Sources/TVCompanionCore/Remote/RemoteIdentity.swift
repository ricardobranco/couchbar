import CryptoKit
import Foundation
import Security

/// The client certificate the TV remembers after pairing, like the one the Google Home app keeps.
public struct RemoteIdentity: @unchecked Sendable {
    let identity: SecIdentity
    let certificate: SecCertificate

    private static let password = "tvcompanion"

    public static func loadOrCreate(in directory: URL) async throws -> RemoteIdentity {
        let file = directory.appending(path: "identity.p12")
        if !FileManager.default.fileExists(atPath: file.path) {
            try await create(at: file)
        }
        return try load(file)
    }

    private static func create(at file: URL) async throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = directory.appending(path: "key.pem")
        let certificate = directory.appending(path: "certificate.pem")
        defer {
            try? FileManager.default.removeItem(at: key)
            try? FileManager.default.removeItem(at: certificate)
        }
        let openssl = URL(fileURLWithPath: "/usr/bin/openssl")
        for arguments in [
            ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "3650",
             "-subj", "/CN=TV Companion", "-keyout", key.path, "-out", certificate.path],
            ["pkcs12", "-export", "-inkey", key.path, "-in", certificate.path, "-out", file.path,
             "-name", "TV Companion", "-passout", "pass:\(password)"],
        ] {
            let result = try await Shell.run(openssl, arguments, timeout: 30)
            guard result.succeeded else { throw RemoteError.certificate(result.stderr) }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private static func load(_ file: URL) throws -> RemoteIdentity {
        var options: [String: Any] = [kSecImportExportPassphrase as String: password]
        if #available(macOS 15, *) {
            options[kSecImportToMemoryOnly as String] = true
        }
        var items: CFArray?
        let status = SecPKCS12Import(try Data(contentsOf: file) as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let item = (items as? [[String: Any]])?.first,
              let identityRef = item[kSecImportItemIdentity as String]
        else { throw RemoteError.certificate("Could not read the remote certificate (\(status)).") }
        let identity = identityRef as! SecIdentity
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        guard let certificate else { throw RemoteError.certificate("The remote certificate has no public key.") }
        return RemoteIdentity(identity: identity, certificate: certificate)
    }
}

enum PairingSecret {
    /// The TV shows six hex digits: the first byte is a check on the SHA-256 of both RSA public keys
    /// plus the last two bytes.
    static func make(code: String, client: SecCertificate, server: SecCertificate) throws -> Data {
        guard let codeBytes = Data(hex: code), codeBytes.count == 3 else { throw RemoteError.invalidCode }
        guard let clientKey = rsaComponents(client), let serverKey = rsaComponents(server) else {
            throw RemoteError.certificate("The TV's certificate is not an RSA key.")
        }
        var hash = SHA256()
        hash.update(data: clientKey.modulus)
        hash.update(data: clientKey.exponent)
        hash.update(data: serverKey.modulus)
        hash.update(data: serverKey.exponent)
        hash.update(data: codeBytes.dropFirst())
        let secret = Data(hash.finalize())
        guard secret.first == codeBytes.first else { throw RemoteError.invalidCode }
        return secret
    }

    static func rsaComponents(_ certificate: SecCertificate) -> (modulus: Data, exponent: Data)? {
        guard let key = SecCertificateCopyKey(certificate),
              let der = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else { return nil }
        var reader = DERReader(der)
        guard let sequence = reader.read(tag: 0x30) else { return nil }
        reader = DERReader(sequence)
        guard let modulus = reader.read(tag: 0x02), let exponent = reader.read(tag: 0x02) else { return nil }
        return (Data(modulus.drop { $0 == 0 }), Data(exponent.drop { $0 == 0 }))
    }
}

private struct DERReader {
    private let data: Data
    private var index: Data.Index

    init(_ data: Data) {
        self.data = data
        index = data.startIndex
    }

    mutating func read(tag: UInt8) -> Data? {
        guard index < data.endIndex, data[index] == tag else { return nil }
        index += 1
        guard index < data.endIndex else { return nil }
        var length = Int(data[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count <= 4, data.endIndex - index >= count else { return nil }
            length = data[index ..< index + count].reduce(0) { $0 << 8 | Int($1) }
            index += count
        }
        guard data.endIndex - index >= length else { return nil }
        defer { index += length }
        return Data(data[index ..< index + length])
    }
}

public enum RemoteError: LocalizedError {
    case certificate(String)
    case invalidCode
    case rejected(Int)
    case connectionClosed
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .certificate(let message): message
        case .invalidCode: "That code doesn't match. Check the code on the TV and try again."
        case .rejected(let status): "The TV refused pairing (status \(status))."
        case .connectionClosed: "The TV closed the connection."
        case .timedOut: "The TV did not answer in time."
        }
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
