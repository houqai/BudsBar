import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

// MARK: - Menu bar label

struct MenuBarLabel: View {
    @ObservedObject var buds: BudsController
    @AppStorage("showPercentage") private var showPercentage = true

    private static let on = MenuBarGlyph.image(connected: true)
    private static let off = MenuBarGlyph.image(connected: false)

    var body: some View {
        let connected = buds.status == .connected
        HStack(spacing: 3) {
            Image(nsImage: connected ? Self.on : Self.off)
            if connected, showPercentage, let level = buds.state.wornLevel {
                Text("\(level)%").monospacedDigit()
            }
        }
    }
}

extension BudsState {
    /// Lowest charge among the buds that are out of the case (or both, if both are in it).
    var wornLevel: Int? {
        let worn = [(left, leftInCase), (right, rightInCase)].filter { $0.1 != true }.compactMap { $0.0?.level }
        return worn.min() ?? [left, right].compactMap { $0?.level }.min()
    }
}

// MARK: - Panel

struct PanelView: View {
    @ObservedObject var buds: BudsController
    @AppStorage("colorway") private var colorway: Colorway = .charcoal
    @AppStorage("shortcutEnabled") private var shortcutEnabled = true
    @AppStorage("showPercentage") private var showPercentage = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var live: Bool { buds.status == .connected }
    private var canControl: Bool { live && buds.hasControl }

    var body: some View {
        VStack(spacing: 14) {
            header
            devices
            noiseControl
            Divider()
            settings
            Divider()
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(width: 320)
    }

    // MARK: Header

    private var statusText: String {
        switch buds.status {
        case .notPaired: return "Not paired with this Mac"
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return buds.hasControl ? "Connected" : "Connected · syncing…"
        }
    }

    private var statusColor: Color {
        switch buds.status {
        case .connected: return buds.hasControl ? .green : .orange
        case .connecting: return .orange
        default: return .secondary.opacity(0.6)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(buds.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if buds.isPaired {
                Toggle("Connected", isOn: Binding(
                    get: { buds.status == .connected || buds.status == .connecting },
                    set: { $0 ? buds.connect() : buds.disconnect() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(buds.status == .connecting)
                    .help(live ? "Disconnect" : "Connect")
            }
        }
    }

    // MARK: Devices

    private var devices: some View {
        let s = buds.state
        return HStack(alignment: .top, spacing: 0) {
            DeviceTile(title: "Left", battery: live ? s.left : nil,
                       inCase: live && s.leftInCase == true, dimmed: !live) {
                BudArt(side: .left, colorway: colorway)
            }
            DeviceTile(title: "Right", battery: live ? s.right : nil,
                       inCase: live && s.rightInCase == true, dimmed: !live) {
                BudArt(side: .right, colorway: colorway)
            }
            DeviceTile(title: "Case", battery: live ? s.chargingCase : nil, inCase: false, dimmed: !live) {
                CaseArt(colorway: colorway, ledOn: live && s.chargingCase?.charging == true)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: Noise control

    private var modes: [AncMode] {
        buds.supportsAdaptive ? [.adaptive, .active, .aware, .off] : [.active, .aware, .off]
    }

    private var noiseControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Noise Control")
            HStack(spacing: 4) {
                ForEach(modes, id: \.self) { mode in
                    ModeButton(mode: mode, selected: canControl && buds.state.anc == mode) {
                        withAnimation(.easeOut(duration: 0.15)) { buds.setAnc(mode) }
                    }
                }
            }
            .disabled(!canControl)
            .opacity(canControl ? 1 : 0.45)
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(spacing: 2) {
            SettingRow(symbol: "keyboard", title: "Shortcut ⌃⌥N",
                       detail: "Noise Cancellation ↔ Transparency") {
                Toggle("", isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _ in Shortcut.shared.update() }
            }
            SettingRow(symbol: "battery.75percent", title: "Battery in menu bar") {
                Toggle("", isOn: $showPercentage)
            }
            SettingRow(symbol: "power", title: "Open at login") {
                Toggle("", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            }
            SettingRow(symbol: "paintpalette", title: "Color", detail: colorway.name) {
                HStack(spacing: 3) {
                    ForEach(Colorway.allCases) { c in
                        Swatch(colorway: c, selected: c == colorway) { colorway = c }
                    }
                }
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("login item: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 0) {
            FooterButton(title: "Bluetooth Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer()
            FooterButton(title: "Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

// MARK: - Components

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

struct DeviceTile<Art: View>: View {
    let title: String
    let battery: Battery?
    let inCase: Bool
    let dimmed: Bool
    @ViewBuilder let art: () -> Art

    var body: some View {
        VStack(spacing: 7) {
            art()
                .frame(width: 64, height: 64)
                .saturation(dimmed ? 0.2 : 1)
                .opacity(dimmed ? 0.5 : 1)
            BatteryLabel(battery: battery)
            Text(inCase ? "\(title) · In case" : title)
                .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BatteryLabel: View {
    let battery: Battery?

    var body: some View {
        HStack(spacing: 5) {
            BatteryGlyph(battery: battery)
                .frame(width: 22, height: 10.5)
            Text(battery.map { "\($0.level)%" } ?? "—")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(battery == nil ? .secondary : .primary)
        }
        .frame(height: 16)
    }
}

struct BatteryGlyph: View {
    let battery: Battery?

    private var fill: Color {
        guard let b = battery else { return .clear }
        if b.charging { return .green }
        return b.level <= 20 ? .red : .primary
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width - 2.5
            let h = g.size.height
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
                    .frame(width: w, height: h)
                if let b = battery {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(fill)
                        .frame(width: max(2, (w - 4) * CGFloat(min(max(b.level, 0), 100)) / 100), height: h - 4)
                        .padding(.leading, 2)
                }
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(Color.primary.opacity(0.4))
                    .frame(width: 1.6, height: h * 0.38)
                    .offset(x: w + 0.6)
                if battery?.charging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 0.6)
                        .frame(width: w, height: h)
                }
            }
        }
    }
}

struct ModeButton: View {
    let mode: AncMode
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.accentColor : Color.primary.opacity(hover ? 0.14 : 0.08))
                    Image(systemName: mode.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .frame(width: 40, height: 40)
                Text(mode.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(mode.title)
    }
}

struct SettingRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    @ViewBuilder let trailing: () -> Trailing

    init(symbol: String, title: String, detail: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

struct Swatch: View {
    let colorway: Colorway
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(LinearGradient(colors: [colorway.palette.cap.mix(.white, 0.15), colorway.palette.cap],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                .frame(width: 14, height: 14)
                .padding(2.5)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 1.6 : 0))
        }
        .buttonStyle(.plain)
        .help(colorway.name)
    }
}

struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hover ? 0.09 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - HUD shown when the shortcut is used

struct HUDView: View {
    let mode: AncMode?
    let name: String
    let colorway: Colorway

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(mode == nil ? Color.secondary.opacity(0.35) : Color.accentColor)
                Image(systemName: mode?.symbol ?? "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode?.title ?? "Not connected")
                    .font(.system(size: 13, weight: .semibold))
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            BudArt(side: .left, colorway: colorway)
                .frame(width: 38, height: 38)
                .opacity(mode == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .frame(width: 290, height: 62)
    }
}

final class HUD {
    private var panel: NSPanel?
    private var host: NSHostingView<HUDView>?
    private var hideWork: DispatchWorkItem?

    func show(mode: AncMode?, name: String) {
        let colorway = Colorway(rawValue: UserDefaults.standard.string(forKey: "colorway") ?? "") ?? .charcoal
        let view = HUDView(mode: mode, name: name, colorway: colorway)
        let p = panel ?? makePanel(view)
        panel = p
        host?.rootView = view

        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let size = NSSize(width: 290, height: 62)
        let target = NSRect(x: f.maxX - size.width - 12, y: f.maxY - size.height - 10, width: size.width, height: size.height)

        hideWork?.cancel()
        if !p.isVisible || p.alphaValue < 1 {
            p.setFrame(target.offsetBy(dx: 0, dy: 8), display: true)
            p.alphaValue = 0
            p.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
            p.animator().setFrame(target, display: true)
        }

        let work = DispatchWorkItem { [weak p] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                p?.animator().alphaValue = 0
            }, completionHandler: { p?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func makePanel(_ view: HUDView) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 62),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let fx = NSVisualEffectView()
        fx.material = .popover
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 18
        fx.layer?.cornerCurve = .continuous
        fx.layer?.masksToBounds = true

        let h = NSHostingView(rootView: view)
        h.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(h)
        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            h.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            h.topAnchor.constraint(equalTo: fx.topAnchor),
            h.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        host = h
        p.contentView = fx
        return p
    }
}

// MARK: - Global shortcut (Carbon hot key, no accessibility permission needed)

final class Shortcut {
    static let shared = Shortcut()

    var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var installed = false

    func update() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        guard UserDefaults.standard.object(forKey: "shortcutEnabled") as? Bool ?? true else { return }

        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { Shortcut.shared.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        let id = EventHotKeyID(signature: OSType(0x4255_4453), id: 1)  // 'BUDS'
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
