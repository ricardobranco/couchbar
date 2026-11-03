import SwiftUI
import TVCompanionCore

struct PopupView: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView()
            if let error = controller.lastError ?? controller.mirror.lastError {
                ErrorBanner(message: error) {
                    controller.clearError()
                }
            }
            if controller.isConnected {
                MirrorRow()
                Divider()
                VolumeRow()
                if let nowPlaying = controller.status.nowPlaying {
                    NowPlayingCard(nowPlaying: nowPlaying)
                }
                Divider()
                RemotePad()
                if !controller.inputs.isEmpty {
                    InputsRow()
                }
                if !controller.favoriteApps.isEmpty {
                    AppsGrid()
                }
            } else {
                DisconnectedView()
            }
            Divider()
            FooterView()
        }
        .padding(16)
        .frame(width: 340)
        .background(WindowKeyReader { controller.isPopupVisible = $0 })
    }
}

private struct HeaderView: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: controller.isOn ? "tv.fill" : "tv")
                .font(.title2)
                .foregroundStyle(controller.isOn ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.tvName)
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                controller.togglePower()
            } label: {
                Image(systemName: "power")
                    .font(.title3)
                    .foregroundStyle(controller.isOn ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!controller.isConnected && !controller.canWake)
            .help(controller.isOn ? "Turn the TV off" : "Turn the TV on")
        }
    }

    private var statusText: String {
        switch controller.connection {
        case .searching: "Looking for the TV…"
        case .unavailable: "Not connected"
        case .connected:
            switch controller.status.power {
            case .awake, .dreaming: controller.mirror.isRunning ? "On · Mirroring" : "On"
            case .asleep, .dozing: "Standby"
            case nil: "Connected"
            }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MirrorRow: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        if controller.mirror.isRunning {
            MirroringCard()
        } else {
            HStack(spacing: 8) {
                Button {
                    controller.toggleMirroring()
                } label: {
                    Label("Mirror TV Screen", systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                ScreenshotButton()
            }
        }
    }
}

private struct MirroringCard: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Currently Mirroring")
            Button {
                controller.mirror.bringToFront()
            } label: {
                ZStack {
                    Color.black
                    if let preview = controller.mirrorPreview {
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .colorScheme(.dark)
                    }
                }
                // A fixed height: the menu bar window only grows for content with a definite size, and
                // squeezes a flexible thumbnail to nothing when mirroring starts while it is open.
                .frame(maxWidth: .infinity)
                .frame(height: 162)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Show the mirror window")

            HStack(spacing: 8) {
                Button {
                    controller.toggleMirroring()
                } label: {
                    Text("Stop Mirroring")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                ScreenshotButton()
            }
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        .task(id: controller.isPopupVisible) {
            while controller.isPopupVisible, !Task.isCancelled {
                await controller.refreshMirrorPreview()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct ScreenshotButton: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        Button {
            controller.saveScreenshot()
        } label: {
            Image(systemName: "camera")
        }
        .controlSize(.large)
        .help("Save a TV screenshot to the Desktop and copy it")
    }
}

private struct VolumeRow: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        HStack(spacing: 8) {
            Button {
                controller.press(.volumeMute)
            } label: {
                Image(systemName: "speaker.slash.fill")
            }
            .buttonStyle(.borderless)
            .help("Mute")

            if controller.status.volumeControl == .stepped {
                Text("Volume")
                    .foregroundStyle(.secondary)
                Spacer()
                if let volume = controller.status.volume {
                    Text("\(volume.current)")
                        .font(.title3.monospacedDigit().weight(.medium))
                        .contentTransition(.numericText(value: Double(volume.current)))
                        .animation(.default, value: volume.current)
                }
            } else if let volume = controller.status.volume {
                Slider(
                    value: Binding(
                        get: { Double(controller.displayedVolume ?? volume.current) },
                        set: { controller.previewVolume(Int($0.rounded())) }
                    ),
                    in: Double(volume.range.lowerBound)...Double(volume.range.upperBound)
                ) { editing in
                    if !editing, let target = controller.displayedVolume {
                        controller.setVolume(target)
                    }
                }
                Text("\(controller.displayedVolume ?? volume.current)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 26, alignment: .trailing)
            } else {
                Spacer()
            }

            if controller.status.volumeControl == .stepped {
                ControlGroup {
                    Button {
                        controller.stepVolume(up: false)
                    } label: {
                        Image(systemName: "minus")
                    }
                    Button {
                        controller.stepVolume(up: true)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                .controlSize(.large)
                .frame(width: 96)
                .help("The sound system only takes volume steps")
            } else {
                Button {
                    controller.stepVolume(up: false)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                Button {
                    controller.stepVolume(up: true)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct NowPlayingCard: View {
    @Environment(TVController.self) private var controller
    let nowPlaying: NowPlaying

    var body: some View {
        HStack(spacing: 10) {
            Image(symbol: TVApp(package: nowPlaying.package).symbol)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(nowPlaying.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(nowPlaying.artist ?? TVApp(package: nowPlaying.package).name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 12) {
                Button { controller.press(.previous) } label: { Image(systemName: "backward.fill") }
                Button { controller.press(.playPause) } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                Button { controller.press(.next) } label: { Image(systemName: "forward.fill") }
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct InputsRow: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Inputs")
            HStack(spacing: 5) {
                ForEach(controller.inputs) { input in
                    Button {
                        controller.switchInput(input)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(color(for: input.state))
                                .frame(width: 6, height: 6)
                            Text(controller.preferences.name(for: input))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help(input.state == .disconnected ? "Nothing connected" : "Switch to this input")
                }
            }
        }
    }

    private func color(for state: TVInput.State) -> Color {
        switch state {
        case .connected: .green
        case .standby: .orange
        case .disconnected: .secondary.opacity(0.4)
        }
    }
}

private struct AppsGrid: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Apps")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(controller.favoriteApps) { app in
                    Button {
                        controller.launch(app)
                    } label: {
                        AppTile(app: app, isCurrent: controller.status.foregroundPackage == app.package)
                    }
                    .buttonStyle(.plain)
                    .help(controller.name(for: app))
                }
            }
        }
    }
}

struct AppTile: View {
    @Environment(TVController.self) private var controller
    let app: TVApp
    var isCurrent = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        content
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(shape)
            .contentShape(shape)
            .overlay {
                shape.strokeBorder(isCurrent ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isCurrent ? 2 : 1)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image = controller.appImages[app.package], controller.appArtwork[app.package]?.isBanner == true {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            VStack(spacing: 4) {
                if let image = controller.appImages[app.package] {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                } else {
                    Image(symbol: app.symbol)
                        .font(.title3)
                        .frame(height: 24)
                }
                Text(controller.name(for: app))
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quinary)
        }
    }
}

private struct DisconnectedView: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        VStack(spacing: 10) {
            if controller.connection == .searching {
                ProgressView()
                    .controlSize(.small)
            } else if case .unavailable(let reason) = controller.connection {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Retry") { controller.reconnect() }
                if controller.canWake {
                    Button("Wake TV") { controller.togglePower() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct FooterView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

extension Image {
    init(symbol: String) {
        self.init(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "app" : symbol)
    }
}
