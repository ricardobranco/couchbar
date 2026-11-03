#if DEBUG
import AppKit
import SwiftUI
import TVCompanionCore

enum PreviewData {
    static let info = TVInfo(
        name: "Living room TV",
        serialNumber: "1A2B3C4D5E6F7A8B9",
        macAddress: "02:11:22:33:44:55",
        inputs: [
            TVInput(id: "tuner", kind: .tuner, state: .connected),
            TVInput(id: "hdmi1", kind: .hdmi(port: 1), state: .standby),
            TVInput(id: "hdmi2", kind: .hdmi(port: 2), state: .disconnected),
            TVInput(id: "hdmi3", kind: .hdmi(port: 3), state: .disconnected),
            TVInput(id: "hdmi4", kind: .hdmi(port: 4), state: .connected),
        ],
        apps: TVApp.defaultFavorites.map(TVApp.init)
    )

    static let playing = TVStatus(
        power: .awake,
        volume: VolumeLevel(current: 15, range: 0...100),
        volumeControl: .stepped,
        foregroundPackage: "com.spotify.tv.android",
        nowPlaying: NowPlaying(package: "com.spotify.tv.android", title: "Take It Or Leave It", artist: "The Strokes", isPlaying: true)
    )

    @MainActor static var scenarios: [(name: String, controller: TVController)] {
        [
            ("connected", .preview(info: info, status: playing)),
            ("mirroring", .preview(info: info, status: TVStatus(power: .awake, volume: VolumeLevel(current: 22, range: 0...100), foregroundPackage: "com.google.android.youtube.tv"), mirroring: true)),
            ("disconnected", .preview(connection: .unavailable("No TV found. Check that wireless debugging is on and the Mac is on the same network."), info: nil)),
        ]
    }
}

/// `TVCompanion --render-previews <dir>` writes PNGs of the popup and Settings in light and dark mode.
@MainActor
enum PreviewRenderer {
    static func renderIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-previews"), arguments.indices.contains(flag + 1) else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1])
        DispatchQueue.main.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for scenario in PreviewData.scenarios {
                render(PopupView().environment(scenario.controller), name: "popup-\(scenario.name)", in: directory)
            }
            render(SettingsView().environment(PreviewData.scenarios[0].controller), name: "settings", in: directory)
            exit(0)
        }
    }

    private static func render(_ view: some View, name: String, in directory: URL) {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: .now + 0.3)

            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appending(path: "\(name)-\(suffix).png"))
        }
    }
}

#Preview("Connected") {
    PopupView().environment(PreviewData.scenarios[0].controller)
}

#Preview("Mirroring") {
    PopupView().environment(PreviewData.scenarios[1].controller)
}

#Preview("Disconnected") {
    PopupView().environment(PreviewData.scenarios[2].controller)
}

#Preview("Settings") {
    SettingsView().environment(PreviewData.scenarios[0].controller)
}
#endif
