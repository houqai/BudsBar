import SwiftUI

/// Developer tooling, no Bluetooth needed:
///   BudsBar --render-preview DIR   README screenshots with sample data
///   BudsBar --render-icon FILE     1024×1024 app icon PNG
@MainActor
enum Preview {
    static func render(to dir: String) {
        _ = NSApplication.shared
        let sample = BudsState(left: Battery(level: 82, charging: false),
                               right: Battery(level: 64, charging: false),
                               chargingCase: Battery(level: 47, charging: true),
                               leftInCase: false, rightInCase: true, anc: .active)
        let name = "Pixel Buds Pro"

        for (file, look) in [("panel-light", NSAppearance.Name.aqua), ("panel-dark", .darkAqua)] {
            snapshot(PanelView(buds: BudsController(preview: .connected, state: sample, name: name)),
                     appearance: look, file: "\(dir)/\(file).png", radius: 14)
        }

        for (file, look) in [("colorways-light", NSAppearance.Name.aqua), ("colorways-dark", .darkAqua)] {
            snapshot(HStack(spacing: 22) {
                ForEach(Colorway.allCases) { c in
                    VStack(spacing: 4) {
                        HStack(spacing: -6) {
                            BudArt(side: .left, colorway: c).frame(width: 78, height: 78)
                            BudArt(side: .right, colorway: c).frame(width: 78, height: 78)
                        }
                        CaseArt(colorway: c).frame(width: 104, height: 104)
                        Text(c.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }.padding(24), appearance: look, file: "\(dir)/\(file).png", radius: 18)
        }

        snapshot(HUDView(mode: .active, name: name, colorway: .charcoal),
                 appearance: .darkAqua, file: "\(dir)/hud-dark.png", radius: 18)
        snapshot(HUDView(mode: .aware, name: name, colorway: .charcoal),
                 appearance: .aqua, file: "\(dir)/hud-light.png", radius: 18)
    }

    static func renderIcon(to file: String) {
        _ = NSApplication.shared
        let renderer = ImageRenderer(content: AppIconArt())
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
    }

    private static func snapshot<V: View>(_ view: V, appearance: NSAppearance.Name, file: String, radius: CGFloat) {
        let size = NSHostingController(rootView: view).sizeThatFits(in: NSSize(width: 4000, height: 4000))
        // fill the whole host, which may pad the content when it is laid out in a window
        let content = view.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        export(rep, radius: radius, dark: appearance == .darkAqua, file: file)
    }

    /// Rounded corners, hairline border and a soft shadow on a transparent canvas.
    private static func export(_ rep: NSBitmapImageRep, radius: CGFloat, dark: Bool, file: String) {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        let pad: CGFloat = 28
        let size = NSSize(width: rep.size.width + pad * 2, height: rep.size.height + pad * 2)
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        let rect = NSRect(x: pad, y: pad, width: rep.size.width, height: rep.size.height)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        rep.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()

        (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.1)).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        border.lineWidth = 0.5
        border.stroke()
        NSGraphicsContext.restoreGraphicsState()
        try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
    }
}

/// App icon: the case with a bud in front of it on a soft squircle, on the macOS 1024 grid.
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.97, green: 0.98, blue: 0.99), Color(red: 0.80, green: 0.85, blue: 0.90)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
            CaseArt(colorway: .charcoal, ledOn: true)
                .frame(width: 600, height: 600)
                .offset(x: -48, y: -46)
            BudArt(side: .left, colorway: .charcoal)
                .frame(width: 420, height: 420)
                .offset(x: 150, y: 170)
        }
        .frame(width: 1024, height: 1024)
    }
}
