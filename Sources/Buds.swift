import Combine
import Foundation
import IOBluetooth

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BudsBar.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func reset() { try? Data().write(to: url) }

    static func write(_ s: String) {
        let line = "\(formatter.string(from: Date())) \(s)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}

/// One RFCOMM connection to the Maestro service of a connected Pixel Buds Pro.
final class MaestroLink: NSObject, IOBluetoothRFCOMMChannelDelegate {
    let device: IOBluetoothDevice
    var onState: ((BudsState) -> Void)?
    var onClosed: ((_ wasReady: Bool) -> Void)?

    private(set) var state = BudsState()
    private(set) var isReady = false
    private var channel: IOBluetoothRFCOMMChannel?
    private var rpcChannel: UInt32?
    private let decoder = HDLC.Decoder()
    private var resolveTimeout: Timer?
    private var closed = false

    init(device: IOBluetoothDevice) {
        self.device = device
    }

    static var maestroSDPUUID: IOBluetoothSDPUUID {
        let uuid = UUID(uuidString: Maestro.serviceUUID)!
        var bytes = uuid.uuid
        return withUnsafeBytes(of: &bytes) { IOBluetoothSDPUUID(bytes: $0.baseAddress!, length: 16) }
    }

    func start() {
        if let id = rfcommChannelID() {
            open(channelID: id)
        } else {
            Log.write("maestro service not in SDP cache, querying device")
            device.performSDPQuery(self)
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard !closed else { return }
        Log.write("sdp query complete, status \(status)")
        if let id = rfcommChannelID() {
            open(channelID: id)
        } else {
            Log.write("device does not advertise the Maestro service")
            finish()
        }
    }

    private func rfcommChannelID() -> BluetoothRFCOMMChannelID? {
        guard let record = device.getServiceRecord(for: Self.maestroSDPUUID) else { return nil }
        var id: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&id) == kIOReturnSuccess else { return nil }
        return id
    }

    private func open(channelID: BluetoothRFCOMMChannelID) {
        Log.write("opening RFCOMM channel \(channelID)")
        var ch: IOBluetoothRFCOMMChannel?
        let r = device.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
        if r != kIOReturnSuccess {
            Log.write("openRFCOMMChannelAsync failed: \(String(format: "0x%08x", r))")
            finish()
            return
        }
        channel = ch
    }

    func close() {
        guard !closed else { return }
        closed = true
        resolveTimeout?.invalidate()
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
    }

    private func finish() {
        let wasReady = isReady
        close()
        onClosed?(wasReady)
    }

    // MARK: RFCOMM delegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard error == kIOReturnSuccess else {
            Log.write("RFCOMM open failed: \(String(format: "0x%08x", error))")
            finish()
            return
        }
        channel = rfcommChannel
        Log.write("RFCOMM open, mtu \(rfcommChannel.getMTU()); resolving rpc channel")
        for c in Maestro.candidateChannels {
            send(RpcPacket(type: .request, channel: c, service: Maestro.service,
                           method: Maestro.getSoftwareInfo, callId: 0xFFFF_FFFF))
        }
        resolveTimeout = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self, self.rpcChannel == nil else { return }
            Log.write("no answer from any rpc channel")
            self.finish()
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        Log.write("RFCOMM closed by remote")
        guard !closed else { return }
        finish()
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        for frame in decoder.feed(bytes) {
            guard frame.control == 0x03, let p = RpcPacket(decoding: frame.data) else {
                Log.write("unparsed frame: \(frame.data.hex)")
                continue
            }
            handle(p)
        }
    }

    // MARK: RPC

    private func send(_ p: RpcPacket) {
        guard let ch = channel, let address = Maestro.address(forChannel: p.channel) else { return }
        var frame = HDLC.encode(address: address, data: p.encode())
        let mtu = max(Int(ch.getMTU()), 16)
        var offset = 0
        while offset < frame.count {
            let n = min(mtu, frame.count - offset)
            let r = frame.withUnsafeMutableBytes { ch.writeSync($0.baseAddress! + offset, length: UInt16(n)) }
            if r != kIOReturnSuccess {
                Log.write("write failed: \(String(format: "0x%08x", r))")
                return
            }
            offset += n
        }
    }

    private func call(_ method: UInt32, _ payload: [UInt8] = []) {
        guard let c = rpcChannel else { return }
        send(RpcPacket(type: .request, channel: c, service: Maestro.service, method: method, payload: payload))
    }

    private func handle(_ p: RpcPacket) {
        guard p.service == Maestro.service else { return }

        switch RpcPacket.Kind(rawValue: p.type) {
        case .response where p.method == Maestro.getSoftwareInfo:
            guard rpcChannel == nil, p.status == 0 else { return }
            rpcChannel = p.channel
            resolveTimeout?.invalidate()
            Log.write("rpc channel resolved: \(p.channel)")
            call(Maestro.subscribeRuntimeInfo)
            call(Maestro.subscribeSettings)
            call(Maestro.readSetting, PB.uint(4, Maestro.currentAncSettingId))
            isReady = true
            onState?(state)

        case .response where p.method == Maestro.readSetting,
             .serverStream where p.method == Maestro.subscribeSettings:
            guard p.status == 0, let m = PBMessage(p.payload) else {
                Log.write("settings rpc status \(p.status)")
                return
            }
            update { $0.apply(settings: m) }

        case .serverStream where p.method == Maestro.subscribeRuntimeInfo:
            guard let m = PBMessage(p.payload) else { return }
            update { $0.apply(runtimeInfo: m) }

        case .response where p.method == Maestro.writeSetting:
            if p.status != 0 {
                Log.write("write setting failed, status \(p.status)")
                call(Maestro.readSetting, PB.uint(4, Maestro.currentAncSettingId))
            }

        case .response where p.method == Maestro.subscribeRuntimeInfo:
            Log.write("runtime info stream ended, resubscribing")
            call(Maestro.subscribeRuntimeInfo)

        case .response where p.method == Maestro.subscribeSettings:
            Log.write("settings stream ended, resubscribing")
            call(Maestro.subscribeSettings)

        default:
            Log.write("rpc type \(p.type) ch \(p.channel) method \(String(format: "%08x", p.method)) status \(p.status)")
        }
    }

    private func update(_ change: (inout BudsState) -> Void) {
        var s = state
        change(&s)
        guard s != state else { return }
        state = s
        Log.write("state: L=\(s.left.map { "\($0.level)" } ?? "-") R=\(s.right.map { "\($0.level)" } ?? "-") "
            + "case=\(s.chargingCase.map { "\($0.level)" } ?? "-") anc=\(s.anc.map { "\($0)" } ?? "-")")
        onState?(state)
    }

    func setAnc(_ mode: AncMode) {
        // WriteSettingMsg { setting = 4: SettingValue { current_ancr_state = 13 } }
        call(Maestro.writeSetting, PB.bytes(4, PB.uint(13, UInt64(mode.rawValue))))
        update { $0.anc = mode }
    }
}

/// Finds the paired Pixel Buds, follows connect/disconnect and keeps a Maestro link open.
final class BudsController: NSObject, ObservableObject {
    enum Status { case notPaired, disconnected, connecting, connected }

    static let shared = BudsController()

    @Published private(set) var status: Status = .notPaired
    @Published private(set) var state = BudsState()
    @Published private(set) var hasControl = false
    @Published private(set) var name = "Pixel Buds Pro"

    private(set) var device: IOBluetoothDevice?
    private var link: MaestroLink?
    private var retryWork: DispatchWorkItem?
    private var failures = 0
    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNote: IOBluetoothUserNotification?
    private var isPreview = false

    var isPaired: Bool { device != nil || (isPreview && status != .notPaired) }
    var supportsAdaptive: Bool { name.localizedCaseInsensitiveContains("Pro 2") }

    override init() { super.init() }

    /// Static instance for design previews; never touches Bluetooth.
    init(preview status: Status, state: BudsState, name: String = "Pixel Buds Pro") {
        super.init()
        isPreview = true
        self.status = status
        self.state = state
        self.name = name
        hasControl = status == .connected
    }

    func start() {
        guard !isPreview else { return }
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(deviceConnected(_:device:)))
        findDevice()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func findDevice() {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let saved = UserDefaults.standard.string(forKey: "deviceAddress")
        device = paired.first { $0.addressString == saved }
            ?? paired.first { $0.getServiceRecord(for: MaestroLink.maestroSDPUUID) != nil }
            ?? paired.first { ($0.name ?? "").localizedCaseInsensitiveContains("Pixel Buds") }
        if let d = device {
            UserDefaults.standard.set(d.addressString, forKey: "deviceAddress")
            name = d.name ?? name
            Log.write("device: \(d.name ?? "?") \(d.addressString ?? "?") connected=\(d.isConnected())")
        } else {
            Log.write("no Pixel Buds among \(paired.count) paired devices")
        }
        refresh()
    }

    private func refresh() {
        guard let d = device else {
            status = .notPaired
            return
        }
        if d.isConnected() {
            if disconnectNote == nil {
                disconnectNote = d.register(forDisconnectNotification: self,
                                            selector: #selector(deviceDisconnected(_:device:)))
            }
            if status != .connected { status = .connected }
            if link == nil, retryWork == nil, failures <= 5 { scheduleLink(after: 1.5) }
        } else if status != .connecting {
            status = .disconnected
        }
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device d: IOBluetoothDevice) {
        if device == nil, (d.name ?? "").localizedCaseInsensitiveContains("Pixel Buds") { device = d }
        guard d.addressString == device?.addressString else { return }
        Log.write("device connected")
        device = d
        name = d.name ?? name
        failures = 0
        refresh()
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device d: IOBluetoothDevice) {
        Log.write("device disconnected")
        disconnectNote?.unregister()
        disconnectNote = nil
        dropLink()
        state = BudsState()
        status = .disconnected
    }

    private func scheduleLink(after delay: TimeInterval) {
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.retryWork = nil
            self?.openLink()
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func openLink() {
        guard let d = device, d.isConnected(), link == nil else { return }
        let l = MaestroLink(device: d)
        l.onState = { [weak self] s in
            guard let self else { return }
            self.failures = 0
            if !self.hasControl { self.hasControl = true }
            if self.state != s { self.state = s }
        }
        l.onClosed = { [weak self] _ in
            guard let self else { return }
            self.link = nil
            self.hasControl = false
            self.failures += 1
            if d.isConnected(), self.failures <= 5 {
                self.scheduleLink(after: Double(min(self.failures * 5, 30)))
            }
        }
        link = l
        l.start()
    }

    private func dropLink() {
        retryWork?.cancel()
        retryWork = nil
        link?.onClosed = nil
        link?.close()
        link = nil
        hasControl = false
    }

    // MARK: Actions

    func setAnc(_ mode: AncMode) {
        if isPreview { state.anc = mode }
        link?.setAnc(mode)
    }

    /// Shortcut: Noise Cancellation <-> Transparency (Off goes to Noise Cancellation).
    @discardableResult
    func toggleAnc() -> AncMode? {
        guard hasControl else { return nil }
        let next: AncMode = state.anc == .active ? .aware : .active
        setAnc(next)
        return next
    }

    func connect() {
        guard let d = device, !d.isConnected() else { return }
        status = .connecting
        d.openConnection(self)
    }

    @objc func connectionComplete(_ d: IOBluetoothDevice!, status: IOReturn) {
        Log.write("connection complete: \(String(format: "0x%08x", status))")
        self.status = d.isConnected() ? .connected : .disconnected
        refresh()
    }

    func disconnect() {
        guard let d = device, d.isConnected() else { return }
        dropLink()
        d.closeConnection()
    }
}
