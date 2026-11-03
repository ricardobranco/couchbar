import SwiftUI

@main
struct CouchbarApp: App {
    @State private var controller = TVController()

    init() {
        #if DEBUG
        PreviewRenderer.renderIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            PopupView()
                .environment(controller)
        } label: {
            if controller.mirror.isRunning {
                Image(nsImage: .mirroringIndicator)
            } else {
                Image(systemName: controller.isConnected && controller.isOn ? "tv.fill" : "tv")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(controller)
        }
    }
}

private extension NSImage {
    // Not a template image, so the menu bar keeps the colour, like the system screen sharing indicator.
    @MainActor static let mirroringIndicator: NSImage = {
        let image = NSImage(size: NSSize(width: 32, height: 20), flipped: false) { rect in
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "tv.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                let origin = NSPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2)
                symbol.draw(in: NSRect(origin: origin, size: symbol.size))
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Mirroring the TV"
        return image
    }()
}
