// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum PacketKind: UInt8 { case hello = 1, ready, ping, pong, format, video, failure }
struct Packet { let kind: PacketKind; let body: Data }

enum PairError: LocalizedError {
    case message(LocalizedMessage)
    var errorDescription: String? { if case .message(let text) = self { return text.localized }; return nil }
}

enum Wire {
    static let version = 1
    static let maximumPacket = 8 * 1024 * 1024
    static func frame(_ kind: PacketKind, _ body: Data = Data()) -> Data {
        precondition(body.count + 1 <= maximumPacket)
        var result = Data()
        result.appendBE(UInt32(body.count + 1))
        result.append(kind.rawValue)
        result.append(body)
        return result
    }
}

struct PacketParser {
    private var buffer = Data()
    mutating func append(_ bytes: Data) throws -> [Packet] {
        buffer.append(bytes)
        var offset = 0
        var packets: [Packet] = []
        while buffer.count - offset >= 4 {
            let length = Int(buffer.uint32BE(at: offset))
            guard length >= 1, length <= Wire.maximumPacket else {
                throw PairError.message("Invalid or oversized packet")
            }
            guard buffer.count - offset >= length + 4 else { break }
            guard let kind = PacketKind(rawValue: buffer[offset + 4]) else {
                throw PairError.message("Unsupported packet type")
            }
            packets.append(Packet(kind: kind, body: Data(buffer[(offset + 5)..<(offset + 4 + length)])))
            offset += 4 + length
        }
        if offset > 0 { buffer = Data(buffer.dropFirst(offset)) }
        return packets
    }
}

extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
    func uint32BE(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(self[startIndex + offset + $1]) }
    }
    func uint64BE(at offset: Int = 0) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { ($0 << 8) | UInt64(self[startIndex + offset + $1]) }
    }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case extend, mirror
    var id: String { rawValue }
    var title: String { self == .extend ? "Extend" : "Mirror" }
}

enum MirrorSizing {
    // Even pixel dimensions suit H.264; preserve the source aspect ratio.
    static func dimensions(width: Int, height: Int) throws -> (width: Int, height: Int) {
        guard width > 0, height > 0 else {
            throw PairError.message("Cannot scale this screen for mirroring")
        }
        let scale = min(1.0, 1280.0 / Double(width), 800.0 / Double(height))
        let outputWidth = Int(Double(width) * scale) / 2 * 2
        let outputHeight = Int(Double(height) * scale) / 2 * 2
        guard outputWidth >= 16, outputHeight >= 16 else {
            throw PairError.message("Cannot scale this screen for mirroring")
        }
        return (outputWidth, outputHeight)
    }
}

struct SessionHello: Codable, Equatable {
    let version: Int
    let mode: String
    let width: Int
    let height: Int
    let fps: Int
    var isVideo: Bool { DisplayMode(rawValue: mode) != nil }
    func validate() throws {
        let minimumWidth = mode == "mirror" ? 16 : 640
        let minimumHeight = mode == "mirror" ? 16 : 400
        guard version == Wire.version, ["diagnostic", "extend", "mirror"].contains(mode),
              (minimumWidth...1920).contains(width), (minimumHeight...1200).contains(height),
              width % 2 == 0, height % 2 == 0, (1...30).contains(fps) else {
            throw PairError.message("Incompatible protocol version or display settings")
        }
    }
}
