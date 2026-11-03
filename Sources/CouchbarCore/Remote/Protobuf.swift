import Foundation

struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ field: Int, _ value: Int) {
        tag(field, wireType: 0)
        Self.appendVarint(UInt64(bitPattern: Int64(value)), to: &data)
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, wireType: 2)
        Self.appendVarint(UInt64(value.count), to: &data)
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Data(value.utf8))
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        bytes(field, nested.data)
    }

    private mutating func tag(_ field: Int, wireType: Int) {
        Self.appendVarint(UInt64(field << 3 | wireType), to: &data)
    }

    static func appendVarint(_ value: UInt64, to data: inout Data) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
    }

    static func framed(_ message: Data) -> Data {
        var data = Data()
        appendVarint(UInt64(message.count), to: &data)
        data.append(message)
        return data
    }
}

/// A decoded protobuf message: every field number with its values in wire order.
struct ProtoMessage {
    enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    private(set) var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        var index = data.startIndex
        while index < data.endIndex {
            let key = try Self.readVarint(data, &index)
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                fields[field, default: []].append(.varint(try Self.readVarint(data, &index)))
            case 2:
                let length = Int(try Self.readVarint(data, &index))
                guard length <= data.endIndex - index else { throw ProtoError.truncated }
                fields[field, default: []].append(.bytes(data[index ..< index + length]))
                index += length
            case 1:
                guard data.endIndex - index >= 8 else { throw ProtoError.truncated }
                index += 8
            case 5:
                guard data.endIndex - index >= 4 else { throw ProtoError.truncated }
                index += 4
            default:
                throw ProtoError.unsupportedWireType
            }
        }
    }

    func has(_ field: Int) -> Bool { fields[field] != nil }

    func int(_ field: Int) -> Int? {
        guard case .varint(let value) = fields[field]?.last else { return nil }
        return Int(truncatingIfNeeded: value)
    }

    func data(_ field: Int) -> Data? {
        guard case .bytes(let value) = fields[field]?.last else { return nil }
        return Data(value)
    }

    func string(_ field: Int) -> String? {
        data(field).map { String(decoding: $0, as: UTF8.self) }
    }

    func message(_ field: Int) -> ProtoMessage? {
        data(field).flatMap { try? ProtoMessage($0) }
    }

    static func readVarint(_ data: Data, _ index: inout Data.Index) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex {
            let byte = data[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 { return result }
            shift += 7
            guard shift < 64 else { throw ProtoError.malformedVarint }
        }
        throw ProtoError.truncated
    }

    /// Splits complete length-prefixed messages off the front of `buffer`.
    static func takeFrames(from buffer: inout Data) throws -> [Data] {
        var frames: [Data] = []
        while !buffer.isEmpty {
            var index = buffer.startIndex
            let length: Int
            do {
                length = Int(try readVarint(buffer, &index))
            } catch ProtoError.truncated {
                break
            }
            guard buffer.endIndex - index >= length else { break }
            frames.append(Data(buffer[index ..< index + length]))
            buffer = Data(buffer[(index + length)...])
        }
        return frames
    }
}

enum ProtoError: Error {
    case truncated
    case malformedVarint
    case unsupportedWireType
}
