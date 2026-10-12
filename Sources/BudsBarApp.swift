import SwiftUI

@main
struct BudsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            exit(selfTest() ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count {
            Preview.render(to: args[i + 1])
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            Preview.renderIcon(to: args[i + 1])
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(buds: .shared)
        } label: {
            MenuBarLabel(buds: .shared)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hud = HUD()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.reset()
        Log.write("BudsBar started")
        BudsController.shared.start()

        Shortcut.shared.action = { [weak self] in
            let buds = BudsController.shared
            self?.hud.show(mode: buds.toggleAnc(), name: buds.name)
        }
        Shortcut.shared.update()
    }
}
