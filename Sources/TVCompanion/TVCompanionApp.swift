import SwiftUI

@main
struct TVCompanionApp: App {
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
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(controller)
        }
    }

    private var menuBarSymbol: String {
        if controller.mirror.isRunning { return "tv.inset.filled" }
        return controller.isConnected && controller.isOn ? "tv.fill" : "tv"
    }
}
