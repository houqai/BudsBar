// Vector artwork of the Pixel Buds Pro: round touch cap with an angled ear tip,
// and the pebble-shaped charging case. Everything is drawn in a 100×100 space.

import AppKit
import SwiftUI

enum Colorway: String, CaseIterable, Identifiable {
    case charcoal, fog, coral, lemongrass, porcelain, bay

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// cap (outer touch surface), body (in-ear shell), case, ear tip
    var palette: (cap: Color, body: Color, shell: Color, tip: Color) {
        switch self {
        case .charcoal: return (Self.hex(0x4A4D52), Self.hex(0x2E3135), Self.hex(0x3F4247), Self.hex(0x5B5E63))
        case .fog: return (Self.hex(0xBCC9D2), Self.hex(0xE9EDF0), Self.hex(0xD9E0E5), Self.hex(0xC7CDD2))
        case .coral: return (Self.hex(0xE8968A), Self.hex(0xF6DCD5), Self.hex(0xF0C2B8), Self.hex(0xE4CBC5))
        case .lemongrass: return (Self.hex(0xCAD48C), Self.hex(0xF1F3DE), Self.hex(0xDFE5B8), Self.hex(0xD6DAC0))
        case .porcelain: return (Self.hex(0xE3DDD2), Self.hex(0xF8F6F2), Self.hex(0xEDE8DF), Self.hex(0xD9D5CE))
        case .bay: return (Self.hex(0x86ADE0), Self.hex(0xDDE8F6), Self.hex(0xB8CEEB), Self.hex(0xC5D2E2))
        }
    }

    var isDark: Bool { self == .charcoal }
}

enum BudSide { case left, right }

struct BudArt: View {
    var side: BudSide
    var colorway: Colorway

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            ctx.translateBy(x: (size.width - 100 * s) / 2, y: (size.height - 100 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            if side == .right {
                ctx.translateBy(x: 100, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
            draw(&ctx)
        }
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let p = colorway.palette

        // contact shadow
        var shadow = ctx
        shadow.addFilter(.blur(radius: 3))
        shadow.fill(Path(ellipseIn: CGRect(x: 18, y: 86, width: 66, height: 8)), with: .color(.black.opacity(0.22)))

        // ear tip: silicone dome pointing towards the ear canal
        var tip = ctx
        tip.translateBy(x: 79, y: 67)
        tip.rotate(by: .degrees(38))
        tip.fill(Path(ellipseIn: CGRect(x: -13, y: -12, width: 28, height: 24)),
                 with: .linearGradient(Gradient(colors: [p.tip.opacity(0.95), p.tip.mix(.black, 0.25)]),
                                       startPoint: CGPoint(x: -10, y: -10), endPoint: CGPoint(x: 12, y: 12)))
        tip.fill(Path(ellipseIn: CGRect(x: 7, y: -5, width: 7, height: 10)), with: .color(.black.opacity(0.35)))

        // in-ear shell behind the cap
        let shell = Path(ellipseIn: CGRect(x: 26, y: 26, width: 64, height: 58))
        ctx.fill(shell, with: .linearGradient(Gradient(colors: [p.body.mix(.white, 0.25), p.body, p.body.mix(.black, 0.22)]),
                                              startPoint: CGPoint(x: 30, y: 28), endPoint: CGPoint(x: 86, y: 84)))
        ctx.stroke(shell, with: .color(.black.opacity(0.10)), lineWidth: 0.8)

        // cap shadow on the shell
        var capShadow = ctx
        capShadow.addFilter(.blur(radius: 4))
        capShadow.fill(Path(ellipseIn: CGRect(x: 16, y: 18, width: 64, height: 64)), with: .color(.black.opacity(0.25)))

        // cap: the round touch surface
        let cap = Path(ellipseIn: CGRect(x: 11, y: 13, width: 64, height: 64))
        ctx.fill(cap, with: .radialGradient(Gradient(colors: [p.cap.mix(.white, 0.28), p.cap, p.cap.mix(.black, 0.18)]),
                                            center: CGPoint(x: 30, y: 30), startRadius: 2, endRadius: 64))
        ctx.stroke(cap, with: .color(.black.opacity(0.12)), lineWidth: 1)

        // bevel between the rim and the flat touch area
        let face = Path(ellipseIn: CGRect(x: 16, y: 18, width: 54, height: 54))
        ctx.stroke(face, with: .linearGradient(Gradient(colors: [.white.opacity(colorway.isDark ? 0.10 : 0.35), .black.opacity(0.05)]),
                                               startPoint: CGPoint(x: 20, y: 20), endPoint: CGPoint(x: 66, y: 70)), lineWidth: 0.9)

        // specular highlight
        var glow = ctx
        glow.addFilter(.blur(radius: 5))
        glow.fill(Path(ellipseIn: CGRect(x: 24, y: 22, width: 22, height: 14)), with: .color(.white.opacity(colorway.isDark ? 0.12 : 0.35)))

        // microphone port on the rim
        ctx.fill(Path(ellipseIn: CGRect(x: 52.5, y: 16.2, width: 2.6, height: 2.6)), with: .color(.black.opacity(0.45)))
    }
}

struct CaseArt: View {
    var colorway: Colorway
    var ledOn: Bool = false

    /// Superellipse: flatter than an ellipse, rounder than a rounded rect.
    static func pebble(in r: CGRect, top: Double = 2.35, bottom: Double = 2.75) -> Path {
        var path = Path()
        let a = r.width / 2, b = r.height / 2
        for i in 0...180 {
            let t = Double(i) / 180 * 2 * .pi
            let c = cos(t), s = sin(t)
            let n = s < 0 ? top : bottom
            let x = r.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
            let y = r.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            ctx.translateBy(x: (size.width - 100 * s) / 2, y: (size.height - 100 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            draw(&ctx)
        }
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let c = colorway.palette.shell

        var shadow = ctx
        shadow.addFilter(.blur(radius: 3.5))
        shadow.fill(Path(ellipseIn: CGRect(x: 12, y: 80, width: 76, height: 9)), with: .color(.black.opacity(0.24)))

        let body = Self.pebble(in: CGRect(x: 8, y: 19, width: 84, height: 64))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [c.mix(.white, 0.22), c, c.mix(.black, 0.2)]),
                                             startPoint: CGPoint(x: 20, y: 20), endPoint: CGPoint(x: 80, y: 86)))

        var inner = ctx
        inner.clip(to: body)

        // lid seam, curving with the shell
        var seam = Path()
        seam.move(to: CGPoint(x: 4, y: 39))
        seam.addQuadCurve(to: CGPoint(x: 96, y: 39), control: CGPoint(x: 50, y: 46))
        inner.stroke(seam, with: .color(.black.opacity(colorway.isDark ? 0.45 : 0.2)), lineWidth: 1.1)
        inner.stroke(seam.offsetBy(dx: 0, dy: 1.1), with: .color(.white.opacity(colorway.isDark ? 0.1 : 0.45)), lineWidth: 0.7)

        // soft top highlight
        var glow = inner
        glow.addFilter(.blur(radius: 7))
        glow.fill(Path(ellipseIn: CGRect(x: 18, y: 18, width: 44, height: 16)), with: .color(.white.opacity(colorway.isDark ? 0.14 : 0.4)))

        ctx.stroke(body, with: .color(.black.opacity(0.12)), lineWidth: 1)

        // status LED
        let led = CGRect(x: 48.4, y: 56, width: 3.2, height: 3.2)
        if ledOn {
            var halo = ctx
            halo.addFilter(.blur(radius: 2.5))
            halo.fill(Path(ellipseIn: led.insetBy(dx: -2, dy: -2)), with: .color(.green.opacity(0.7)))
            ctx.fill(Path(ellipseIn: led), with: .color(Color(red: 0.55, green: 1, blue: 0.6)))
        } else {
            ctx.fill(Path(ellipseIn: led), with: .color(.black.opacity(colorway.isDark ? 0.5 : 0.18)))
        }
    }
}

extension Color {
    func mix(_ other: Color, _ amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        let t = CGFloat(amount)
        return Color(red: Double(a.redComponent + (b.redComponent - a.redComponent) * t),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * t),
                     blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * t))
    }
}

/// Template glyph for the menu bar: Pixel Buds Pro in 3/4 view, like the panel artwork.
enum MenuBarGlyph {
    /// One bud in a 14×15 box: round cap in front, in-ear shell and ear tip behind it to the lower right.
    private static func drawBud(_ ctx: CGContext, alpha: CGFloat) {
        let ink = NSColor.black.withAlphaComponent(alpha).cgColor
        let cap = CGRect(x: 0.5, y: 0.5, width: 9.0, height: 9.0)

        ctx.setFillColor(ink)
        ctx.fillEllipse(in: CGRect(x: 4.0, y: 3.8, width: 9.6, height: 8.6))
        ctx.saveGState()
        ctx.translateBy(x: 12.0, y: 11.4)
        ctx.rotate(by: 40 * .pi / 180)
        ctx.fillEllipse(in: CGRect(x: -2.3, y: -1.8, width: 4.6, height: 3.6))
        ctx.restoreGState()

        // gap between the cap and the shell
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: cap.insetBy(dx: -1.1, dy: -1.1))
        ctx.setBlendMode(.normal)

        ctx.setFillColor(ink)
        ctx.fillEllipse(in: cap)
    }

    static func image(connected: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 15, height: 15), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: 0.4, y: 0.6)
            drawBud(ctx, alpha: connected ? 1 : 0.4)
            return true
        }
        img.isTemplate = true
        return img
    }
}
