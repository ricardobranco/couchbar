import Foundation
import Testing
@testable import TVCompanionCore

struct ProtobufTests {
    @Test func roundTrip() throws {
        var writer = ProtoWriter()
        writer.varint(1, 2)
        writer.varint(2, 200)
        writer.message(10) {
            $0.string(1, "atvremote")
            $0.string(2, "TV Companion")
        }
        let message = try ProtoMessage(writer.data)
        #expect(message.int(1) == 2)
        #expect(message.int(2) == 200)
        #expect(message.message(10)?.string(2) == "TV Companion")
        #expect(!message.has(11))
    }

    @Test func pairingRequestMatchesReference() {
        var writer = ProtoWriter()
        writer.varint(1, 2)
        writer.varint(2, 200)
        writer.message(10) { $0.string(1, "atvremote") }
        #expect(writer.data == Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0x52, 0x0B, 0x0A, 0x09]) + Data("atvremote".utf8))
    }

    @Test func negativeCursorForEmptyText() throws {
        var writer = ProtoWriter()
        writer.varint(1, -1)
        #expect(writer.data.count == 11)
        #expect(try ProtoMessage(writer.data).int(1) == -1)
    }

    @Test func framesSplitAcrossReads() throws {
        let first = ProtoWriter.framed(Data(repeating: 7, count: 200))
        let second = ProtoWriter.framed(Data([1, 2, 3]))
        var buffer = first.prefix(1)
        #expect(try ProtoMessage.takeFrames(from: &buffer).isEmpty)
        buffer.append(first.dropFirst())
        buffer.append(second.prefix(2))
        let frames = try ProtoMessage.takeFrames(from: &buffer)
        #expect(frames == [Data(repeating: 7, count: 200)])
        buffer.append(second.dropFirst(2))
        #expect(try ProtoMessage.takeFrames(from: &buffer) == [Data([1, 2, 3])])
        #expect(buffer.isEmpty)
    }

    @Test func textFieldFromTV() throws {
        // A show request captured from the TV's Google search field after typing "ola são".
        let raw = Data(hex: "b201391237080712086f6c612073c3a36f1807200728013223536561726368206d6f766965732c2073686f77732c206170707320616e64206d6f7265")!
        let status = try #require(try ProtoMessage(raw).message(22)?.message(2))
        #expect(status.string(2) == "ola são")
        #expect(status.string(6) == "Search movies, shows, apps and more")
    }

    @Test func focusedFieldOnConnect() throws {
        // An app's search field with "q" typed, as the TV reports it right after connecting.
        let raw = Data(hex: "a2013a0a2b081110818002188380801038014001620f636f6d2e6578616d706c652e61707068ffffffffffffffffff01120b082a120171180120012801")!
        let inject = try #require(try ProtoMessage(raw).message(20))
        let status = try #require(inject.message(2))
        #expect(status.string(2) == "q")
        // The counters a batch edit has to carry for the TV to accept it.
        #expect(inject.message(1)?.int(1) == 17)
        #expect(status.int(1) == 42)
    }
}
