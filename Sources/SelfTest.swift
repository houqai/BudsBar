import Foundation

/// `BudsBar --selftest`: checks the protocol encoders against pbpctrl's test vectors.
func selfTest() -> Bool {
    var ok = true
    func check(_ name: String, _ cond: Bool) {
        print(cond ? "ok   " : "FAIL ", name)
        ok = ok && cond
    }

    check("hash service", pwHash("maestro_pw.Maestro") == 0x7EDE_71EA)
    check("hash GetSoftwareInfo", pwHash("GetSoftwareInfo") == 0x7199_FA44)
    check("hash SubscribeToSettingsChanges", pwHash("SubscribeToSettingsChanges") == 0x2821_ADF5)
    check("crc32", HDLC.crc32(Array("test test test".utf8)) == 0x235B_6A02)
    check("addr varint", HDLC.addressVarint(0x87654) == [0xA8, 0xD8, 0x43])
    check("hdlc empty", HDLC.encode(address: 0x010203, data: [])
        == [0x7E, 0x06, 0x08, 0x09, 0x03, 0x8B, 0x3B, 0xF7, 0x42, 0x7E])
    check("hdlc escaped", HDLC.encode(address: 0x010203, data: [0x05, 0x06, 0x07, 0x7D, 0x7E, 0x7F, 0xFF])
        == [0x7E, 0x06, 0x08, 0x09, 0x03, 0x05, 0x06, 0x07, 0x7D, 0x5D, 0x7D, 0x5E, 0x7F, 0xFF, 0xE6, 0x2D, 0x17, 0xC6, 0x7E])

    let p = RpcPacket(type: .serverStream, channel: 21, service: Maestro.service, method: Maestro.subscribeRuntimeInfo,
                      payload: PB.bytes(6, PB.bytes(1, PB.uint(1, 55) + PB.uint(2, 2)) + PB.bytes(2, PB.uint(1, 80) + PB.uint(2, 1)))
                          + PB.bytes(7, PB.uint(2, 1)))
    let wire = HDLC.encode(address: Maestro.address(forChannel: 21)!, data: p.encode())
    let dec = HDLC.Decoder()
    let frames = dec.feed(Array(wire[..<5])) + dec.feed(Array(wire[5...]))
    check("roundtrip frame", frames.count == 1)
    if let f = frames.first, let q = RpcPacket(decoding: f.data), let m = PBMessage(q.payload) {
        check("roundtrip packet", q.channel == 21 && q.method == Maestro.subscribeRuntimeInfo && q.type == 7)
        var s = BudsState()
        s.apply(runtimeInfo: m)
        check("runtime info", s.chargingCase == Battery(level: 55, charging: true)
            && s.left == Battery(level: 80, charging: false) && s.right == nil && s.leftInCase == true)
        s.apply(settings: PBMessage(PB.bytes(4, PB.uint(13, 3)))!)
        check("anc setting", s.anc == .aware)
    } else {
        check("roundtrip decode", false)
    }
    return ok
}
