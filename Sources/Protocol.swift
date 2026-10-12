// Pixel Buds Pro "Maestro" protocol: HDLC framing + Pigweed RPC + protobuf.
// Reverse-engineered by qzed/pbpctrl (Apache-2.0 / MIT); this is a minimal Swift port.

import Foundation

// MARK: - Protobuf (just enough for the messages we need)

enum PB {
    static func varint(_ value: UInt64) -> [UInt8] {
        var v = value
        var out = [UInt8]()
        repeat {
            var b = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }

    static func key(_ field: Int, _ wire: Int) -> [UInt8] { varint(UInt64(field << 3 | wire)) }
    static func uint(_ field: Int, _ v: UInt64) -> [UInt8] { key(field, 0) + varint(v) }
    static func bytes(_ field: Int, _ b: [UInt8]) -> [UInt8] { key(field, 2) + varint(UInt64(b.count)) + b }
    static func fixed32(_ field: Int, _ v: UInt32) -> [UInt8] {
        key(field, 5) + [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
    }
}

enum PBValue {
    case varint(UInt64)
    case fixed32(UInt32)
    case fixed64(UInt64)
    case bytes([UInt8])
}

struct PBMessage {
    let fields: [(Int, PBValue)]

    init?(_ d: [UInt8]) {
        var i = 0
        var out = [(Int, PBValue)]()

        func readVarint() -> UInt64? {
            var r: UInt64 = 0
            var shift: UInt64 = 0
            while i < d.count {
                let b = d[i]
                i += 1
                r |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return r }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }

        while i < d.count {
            guard let k = readVarint() else { return nil }
            let field = Int(k >> 3)
            switch k & 7 {
            case 0:
                guard let v = readVarint() else { return nil }
                out.append((field, .varint(v)))
            case 1:
                guard i + 8 <= d.count else { return nil }
                var v: UInt64 = 0
                for j in 0..<8 { v |= UInt64(d[i + j]) << (8 * UInt64(j)) }
                i += 8
                out.append((field, .fixed64(v)))
            case 2:
                guard let l = readVarint(), l <= UInt64(d.count - i) else { return nil }
                out.append((field, .bytes(Array(d[i..<i + Int(l)]))))
                i += Int(l)
            case 5:
                guard i + 4 <= d.count else { return nil }
                var v: UInt32 = 0
                for j in 0..<4 { v |= UInt32(d[i + j]) << (8 * UInt32(j)) }
                i += 4
                out.append((field, .fixed32(v)))
            default:
                return nil
            }
        }
        fields = out
    }

    func varint(_ f: Int) -> UInt64? {
        for (n, v) in fields.reversed() where n == f { if case .varint(let x) = v { return x } }
        return nil
    }

    func fixed32(_ f: Int) -> UInt32? {
        for (n, v) in fields.reversed() where n == f { if case .fixed32(let x) = v { return x } }
        return nil
    }

    func bytes(_ f: Int) -> [UInt8]? {
        for (n, v) in fields.reversed() where n == f { if case .bytes(let x) = v { return x } }
        return nil
    }

    func message(_ f: Int) -> PBMessage? { bytes(f).flatMap { PBMessage($0) } }
}

// MARK: - HDLC framing

enum HDLC {
    static func crc32(_ data: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data {
            c ^= UInt32(b)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
        }
        return ~c
    }

    /// HDLC address varint: 7 bits per byte, shifted left by one; LSB marks the last byte.
    static func addressVarint(_ value: UInt32) -> [UInt8] {
        var n = value
        var out = [UInt8]()
        while (n >> 7) != 0 {
            out.append(UInt8(n & 0x7F) << 1)
            n >>= 7
        }
        out.append((UInt8(n & 0x7F) << 1) | 1)
        return out
    }

    static func encode(address: UInt32, control: UInt8 = 0x03, data: [UInt8]) -> [UInt8] {
        let body = addressVarint(address) + [control] + data
        let crc = crc32(body)
        let full = body + [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8((crc >> 16) & 0xFF), UInt8(crc >> 24)]
        var out: [UInt8] = [0x7E]
        for b in full {
            if b == 0x7E || b == 0x7D { out += [0x7D, b ^ 0x20] } else { out.append(b) }
        }
        out.append(0x7E)
        return out
    }

    struct Frame {
        let address: UInt32
        let control: UInt8
        let data: [UInt8]
    }

    final class Decoder {
        private var buf = [UInt8]()
        private var inFrame = false
        private var escaped = false

        func feed(_ bytes: [UInt8]) -> [Frame] {
            var frames = [Frame]()
            for b in bytes {
                if b == 0x7E {
                    if inFrame, !buf.isEmpty, let f = Decoder.parse(buf) { frames.append(f) }
                    buf.removeAll(keepingCapacity: true)
                    inFrame = true
                    escaped = false
                    continue
                }
                guard inFrame else { continue }
                if escaped {
                    buf.append(b ^ 0x20)
                    escaped = false
                } else if b == 0x7D {
                    escaped = true
                } else {
                    buf.append(b)
                }
                if buf.count > 1 << 16 {
                    buf.removeAll()
                    inFrame = false
                }
            }
            return frames
        }

        private static func parse(_ f: [UInt8]) -> Frame? {
            guard f.count >= 6 else { return nil }
            let body = Array(f[0..<(f.count - 4)])
            let c = f[(f.count - 4)...].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            guard HDLC.crc32(body) == c else {
                Log.write("hdlc: bad crc, dropping frame of \(f.count) bytes")
                return nil
            }
            var address: UInt32 = 0
            var i = 0
            while i < body.count {
                let b = body[i]
                address |= UInt32(b >> 1) << (7 * UInt32(i))
                i += 1
                if b & 1 == 1 { break }
            }
            guard i < body.count else { return nil }
            return Frame(address: address, control: body[i], data: Array(body[(i + 1)...]))
        }
    }
}

// MARK: - Pigweed RPC

/// pw_rpc service/method id: 65599-hash of the name.
func pwHash(_ s: String) -> UInt32 {
    var hash = UInt32(truncatingIfNeeded: s.utf8.count)
    var coef: UInt32 = 65599
    for c in s.unicodeScalars {
        hash = hash &+ coef &* c.value
        coef = coef &* 65599
    }
    return hash
}

struct RpcPacket {
    enum Kind: UInt64 {
        case request = 0, response = 1, serverError = 5, serverStream = 7, clientError = 4
    }

    var type: UInt64 = Kind.request.rawValue
    var channel: UInt32 = 0
    var service: UInt32 = 0
    var method: UInt32 = 0
    var payload: [UInt8] = []
    var status: UInt64 = 0
    var callId: UInt32 = 0

    init(type: Kind, channel: UInt32, service: UInt32, method: UInt32, payload: [UInt8] = [], callId: UInt32 = 0) {
        self.type = type.rawValue
        self.channel = channel
        self.service = service
        self.method = method
        self.payload = payload
        self.callId = callId
    }

    init?(decoding d: [UInt8]) {
        guard let m = PBMessage(d) else { return nil }
        type = m.varint(1) ?? 0
        channel = UInt32(truncatingIfNeeded: m.varint(2) ?? 0)
        service = m.fixed32(3) ?? 0
        method = m.fixed32(4) ?? 0
        payload = m.bytes(5) ?? []
        status = m.varint(6) ?? 0
        callId = UInt32(truncatingIfNeeded: m.varint(7) ?? 0)
    }

    // proto3: default values are omitted, same as prost does.
    func encode() -> [UInt8] {
        var o = [UInt8]()
        if type != 0 { o += PB.uint(1, type) }
        if channel != 0 { o += PB.uint(2, UInt64(channel)) }
        if service != 0 { o += PB.fixed32(3, service) }
        if method != 0 { o += PB.fixed32(4, method) }
        if !payload.isEmpty { o += PB.bytes(5, payload) }
        if status != 0 { o += PB.uint(6, status) }
        if callId != 0 { o += PB.uint(7, UInt64(callId)) }
        return o
    }
}

// MARK: - Maestro addressing

enum Maestro {
    static let serviceUUID = "25e97ff7-24ce-4c4c-8951-f764a708f7b5"

    static let service = pwHash("maestro_pw.Maestro")
    static let getSoftwareInfo = pwHash("GetSoftwareInfo")
    static let subscribeRuntimeInfo = pwHash("SubscribeRuntimeInfo")
    static let writeSetting = pwHash("WriteSetting")
    static let readSetting = pwHash("ReadSetting")
    static let subscribeSettings = pwHash("SubscribeToSettingsChanges")

    static let currentAncSettingId: UInt64 = 13

    /// Channels to probe: Maestro A/B talking to case, left or right BT core.
    static let candidateChannels: [UInt32] = [18, 19, 21, 23, 24, 26]

    static func address(forChannel c: UInt32) -> UInt32? {
        // channel -> (source peer, target peer); 10 = MaestroA, 13 = MaestroB,
        // 2 = case, 3 = left core, 4 = right core, 5/6 = left/right sensor hub.
        let peers: [UInt32: (UInt32, UInt32)] = [
            18: (10, 2), 19: (10, 3), 20: (10, 5), 21: (10, 4), 22: (10, 6),
            23: (13, 2), 24: (13, 3), 25: (13, 5), 26: (13, 4), 27: (13, 6),
        ]
        guard let (s, t) = peers[c] else { return nil }
        return ((s & 0xF) << 6) | ((t & 0xF) << 10)
    }
}

// MARK: - Device state

enum AncMode: Int, CaseIterable {
    case active = 2, aware = 3, off = 1, adaptive = 4

    var title: String {
        switch self {
        case .active: return "Noise Cancellation"
        case .aware: return "Transparency"
        case .off: return "Off"
        case .adaptive: return "Adaptive"
        }
    }

    var symbol: String {
        switch self {
        case .active: return "person.and.background.dotted"
        case .aware: return "person.wave.2.fill"
        case .off: return "person.fill"
        case .adaptive: return "wand.and.stars"
        }
    }
}

struct Battery: Equatable {
    var level: Int
    var charging: Bool
}

struct BudsState: Equatable {
    var left: Battery?
    var right: Battery?
    var chargingCase: Battery?
    var leftInCase: Bool?
    var rightInCase: Bool?
    var anc: AncMode?

    /// RuntimeInfo { battery_info = 6 { case = 1, left = 2, right = 3 }, placement = 7 }
    mutating func apply(runtimeInfo m: PBMessage) {
        func battery(_ msg: PBMessage?) -> Battery? {
            guard let msg else { return nil }
            return Battery(level: Int(msg.varint(1) ?? 0), charging: msg.varint(2) == 2)
        }
        if let b = m.message(6) {
            chargingCase = battery(b.message(1))
            left = battery(b.message(2))
            right = battery(b.message(3))
        }
        if let p = m.message(7) {
            rightInCase = (p.varint(1) ?? 0) != 0
            leftInCase = (p.varint(2) ?? 0) != 0
        }
    }

    /// SettingsRsp { value = 4: SettingValue { current_ancr_state = 13 } }
    mutating func apply(settings m: PBMessage) {
        if let v = m.message(4)?.varint(13), let mode = AncMode(rawValue: Int(v)) {
            anc = mode
        }
    }
}
