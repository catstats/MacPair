// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum PacketKind: UInt8 { case hello = 1, ready, ping, pong, format, video, failure }
struct Packet { let kind: PacketKind; let body: Data }

enum PairError: LocalizedError {
    case message(LocalizedMessage)
    var errorDescription: String? { if case .message(let text) = self { return text.localized }; return nil }
}

enum Wire {
    static let version = 2
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

enum ResolutionPreset: String, Codable, CaseIterable, Identifiable {
    case largerText, recommended = "default", moreSpace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .largerText: return "Larger Text"
        case .recommended: return "Default (Recommended)"
        case .moreSpace: return "More Space"
        }
    }
    var factor: Double {
        switch self { case .largerText: return 0.8; case .recommended: return 1; case .moreSpace: return 1.25 }
    }
}

struct DisplayGeometry: Codable, Equatable {
    let logicalWidth: Int
    let logicalHeight: Int
    let backingWidth: Int
    let backingHeight: Int
    let scale: Int
    func validate() throws {
        guard (1...2).contains(scale), (320...8192).contains(logicalWidth),
              (200...8192).contains(logicalHeight),
              backingWidth == logicalWidth * scale, backingHeight == logicalHeight * scale else {
            throw PairError.message("The display Mac reported invalid screen dimensions")
        }
    }
}

struct ReceiverDisplayInfo: Codable, Equatable {
    let name: String
    let screen: DisplayGeometry
    let viewport: DisplayGeometry
    func validate() throws {
        try screen.validate()
        try viewport.validate()
        guard name.utf8.count <= 256, viewport.scale == screen.scale,
              viewport.logicalWidth <= screen.logicalWidth + 1,
              viewport.logicalHeight <= screen.logicalHeight + 1 else {
            throw PairError.message("The display Mac reported invalid screen dimensions")
        }
    }
}

struct VirtualCanvas: Codable, Equatable {
    let width: Int // Desktop points, not encoded pixels.
    let height: Int
    let scale: Int
    var pixelWidth: Int { width * scale }
    var pixelHeight: Int { height * scale }
    func validate() throws {
        guard (1...2).contains(scale), (320...5120).contains(width), (200...5120).contains(height),
              pixelWidth <= 5120, pixelHeight <= 5120, pixelWidth * pixelHeight <= 16_777_216,
              pixelWidth % 2 == 0, pixelHeight % 2 == 0 else {
            throw PairError.message("This resolution is too large for this prototype. Choose Larger Text and reconnect.")
        }
    }
}

enum ResolutionSizing {
    static func canvas(for display: ReceiverDisplayInfo, preset: ResolutionPreset) throws -> VirtualCanvas {
        try display.validate()
        let viewport = display.viewport
        // Retina encodes two pixels per desktop point. At 1× round to even
        // dimensions for H.264; aspect error stays below two desktop points.
        let step = viewport.scale == 2 ? 1.0 : 2.0
        let width = Int((Double(viewport.logicalWidth) * preset.factor / step).rounded()) * Int(step)
        let height = Int((Double(viewport.logicalHeight) * preset.factor / step).rounded()) * Int(step)
        let canvas = VirtualCanvas(width: width, height: height, scale: viewport.scale)
        try canvas.validate()
        return canvas
    }
}

struct SessionHello: Codable, Equatable {
    let version: Int
    let mode: String
    let width: Int // Encoded pixel dimensions after negotiation.
    let height: Int
    let fps: Int
    let resolution: ResolutionPreset
    let receiver: ReceiverDisplayInfo?
    let canvas: VirtualCanvas?
    var isVideo: Bool { DisplayMode(rawValue: mode) != nil }

    init(version: Int, mode: String, width: Int, height: Int, fps: Int,
         resolution: ResolutionPreset = .recommended, receiver: ReceiverDisplayInfo? = nil,
         canvas: VirtualCanvas? = nil) {
        self.version = version; self.mode = mode; self.width = width; self.height = height; self.fps = fps
        self.resolution = resolution; self.receiver = receiver; self.canvas = canvas
    }
    private enum CodingKeys: String, CodingKey { case version, mode, width, height, fps, resolution, receiver, canvas }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        mode = try values.decode(String.self, forKey: .mode)
        width = try values.decode(Int.self, forKey: .width)
        height = try values.decode(Int.self, forKey: .height)
        fps = try values.decode(Int.self, forKey: .fps)
        // Decode v1 messages far enough to show an actionable version error.
        resolution = try values.decodeIfPresent(ResolutionPreset.self, forKey: .resolution) ?? .recommended
        receiver = try values.decodeIfPresent(ReceiverDisplayInfo.self, forKey: .receiver)
        canvas = try values.decodeIfPresent(VirtualCanvas.self, forKey: .canvas)
    }
    func validate() throws {
        guard version == Wire.version else {
            throw PairError.message("MacPair versions differ. Update MacPair on both Macs and reconnect.")
        }
        let maxWidth = mode == "extend" ? 5120 : 1280
        let maxHeight = mode == "extend" ? 5120 : 800
        guard ["diagnostic", "extend", "mirror"].contains(mode),
              (16...maxWidth).contains(width), (16...maxHeight).contains(height),
              width * height <= 16_777_216, width % 2 == 0, height % 2 == 0, (1...30).contains(fps) else {
            throw PairError.message("Incompatible protocol version or display settings")
        }
        try receiver?.validate()
        try canvas?.validate()
    }
    func validateRequest() throws {
        try validate()
        guard receiver == nil, canvas == nil,
              mode == "extend" || resolution == .recommended else {
            throw PairError.message("The display returned incompatible parameters")
        }
    }
    func negotiated(for display: ReceiverDisplayInfo) throws -> SessionHello {
        try validateRequest()
        guard isVideo else { return self }
        try display.validate()
        let canvas = mode == "extend" ? try ResolutionSizing.canvas(for: display, preset: resolution) : nil
        let result = SessionHello(version: version, mode: mode, width: canvas?.pixelWidth ?? width,
            height: canvas?.pixelHeight ?? height, fps: fps, resolution: resolution, receiver: display, canvas: canvas)
        try result.validate()
        return result
    }
    func validateResponse(to request: SessionHello) throws {
        try validate()
        try request.validateRequest()
        let expected: SessionHello
        if request.isVideo {
            guard let receiver else { throw PairError.message("The display returned incompatible parameters") }
            expected = try request.negotiated(for: receiver)
        } else { expected = request }
        guard self == expected else { throw PairError.message("The display returned incompatible parameters") }
    }
}
