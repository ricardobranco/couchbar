import ServiceManagement
import SwiftUI
import CouchbarCore

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettings()
                .tabItem { Label("Connection", systemImage: "network") }
            MirrorSettings()
                .tabItem { Label("Mirroring", systemImage: "rectangle.on.rectangle") }
            InputSettings()
                .tabItem { Label("Inputs", systemImage: "cable.connector") }
            AppSettings()
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
        }
        .frame(width: 480, height: 400)
    }
}

private struct ConnectionSettings: View {
    @Environment(TVController.self) private var controller
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var preferences = controller.preferences
        Form {
            Section {
                LabeledContent("TV", value: controller.info?.name ?? "Not connected")
                if let serial = preferences.serialNumber {
                    LabeledContent("Serial number", value: serial)
                }
                if let mac = preferences.macAddress {
                    LabeledContent("MAC address (Wake on LAN)", value: mac)
                }
                TextField("Manual address", text: $preferences.manualAddress, prompt: Text("Found automatically"))
                HStack {
                    Spacer()
                    Button("Forget TV") {
                        preferences.serialNumber = nil
                        preferences.macAddress = nil
                        controller.reconnect()
                    }
                    Button("Reconnect") { controller.reconnect() }
                }
            } footer: {
                Text("Turn on Wireless debugging in the TV's Developer options and pair this Mac once with `adb pair`. The TV is then found on the network automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            KeyboardPairingSection()
            Section {
                TextField("adb", text: $preferences.adbPath, prompt: Text(ADB.locate()?.executable.path ?? "Not found"))
                TextField("scrcpy", text: $preferences.scrcpyPath, prompt: Text(Scrcpy.locate()?.path ?? "Not found"))
            } header: {
                Text("Tools")
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

private struct KeyboardPairingSection: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        Section {
            LabeledContent("Keyboard") {
                if controller.preferences.keyboardPaired {
                    HStack {
                        Text(controller.isKeyboardConnected ? "Connected" : "Paired")
                            .foregroundStyle(.secondary)
                        Button("Unpair") { controller.unpairKeyboard() }
                    }
                } else if controller.keyboardPairing == .starting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Pair…") { controller.startKeyboardPairing() }
                        .disabled(!controller.isConnected || controller.keyboardPairing != .idle)
                }
            }
            if controller.keyboardPairing == .idle, let error = controller.keyboardError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Pairing works like the Google Home app: the TV shows a code to enter here. Typing in the popup then follows the text field selected on the TV, with any characters.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: Binding(
            get: { controller.keyboardPairing == .waitingForCode || controller.keyboardPairing == .finishing },
            set: { if !$0 { controller.cancelKeyboardPairing() } }
        )) {
            PairingCodeSheet()
        }
    }
}

struct PairingCodeSheet: View {
    @Environment(TVController.self) private var controller
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            Text("Enter the code shown on the TV")
                .font(.headline)
            Text("\(controller.tvName) is showing a six-character pairing code.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("", text: $code, prompt: Text("000000"))
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                .frame(width: 180)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                .focused($focused)
                .onChange(of: code) { _, new in
                    let cleaned = String(new.uppercased().filter(\.isHexDigit).prefix(6))
                    if cleaned != new { code = cleaned }
                }
                .onSubmit(pair)
            if let error = controller.keyboardError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Button("Cancel", role: .cancel) { controller.cancelKeyboardPairing() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if controller.keyboardPairing == .finishing {
                    ProgressView().controlSize(.small)
                }
                Button("Pair", action: pair)
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.count != 6 || controller.keyboardPairing == .finishing)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear {
            focused = true
            NSApp.activate()
        }
    }

    private func pair() {
        guard code.count == 6 else { return }
        controller.finishKeyboardPairing(code: code)
    }
}

private struct MirrorSettings: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        @Bindable var preferences = controller.preferences
        Form {
            Section {
                Picker("Resolution", selection: $preferences.mirror.maxSize) {
                    Text("720p").tag(1280)
                    Text("1080p").tag(1920)
                    Text("4K").tag(3840)
                }
                Picker("Bit rate", selection: $preferences.mirror.bitRateMbps) {
                    ForEach([4, 8, 16, 24], id: \.self) { Text("\($0) Mbps").tag($0) }
                }
                Picker("Frame rate", selection: $preferences.mirror.maxFPS) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
            }
            Section {
                Toggle("Play TV sound on this Mac", isOn: $preferences.mirror.forwardAudio)
                Toggle("Control the TV with keyboard and mouse", isOn: $preferences.mirror.allowControl)
                Toggle("Keep window on top", isOn: $preferences.mirror.alwaysOnTop)
            } footer: {
                Text("Mirroring uses scrcpy. HDMI inputs, Live TV and DRM-protected apps such as Netflix show black: Android cannot capture them. Changes apply the next time mirroring starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

private struct InputSettings: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        Form {
            if controller.inputs.isEmpty {
                Text("Connect to the TV to rename its inputs.")
                    .foregroundStyle(.secondary)
            }
            ForEach(controller.inputs) { input in
                TextField(input.defaultName, text: binding(for: input), prompt: Text(input.defaultName))
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for input: TVInput) -> Binding<String> {
        Binding(
            get: { controller.preferences.inputNames[input.id] ?? "" },
            set: { controller.preferences.inputNames[input.id] = $0 }
        )
    }
}

private struct AppSettings: View {
    @Environment(TVController.self) private var controller

    var body: some View {
        Form {
            if let apps = controller.info?.apps {
                Section {
                    ForEach(apps) { app in
                        Toggle(isOn: binding(for: app)) {
                            HStack(spacing: 10) {
                                AppTile(app: app)
                                    .frame(width: 48)
                                Text(controller.name(for: app))
                            }
                        }
                    }
                } footer: {
                    Text("Favorites appear in the menu bar popup in this order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Connect to the TV to choose favorite apps.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for app: TVApp) -> Binding<Bool> {
        Binding(
            get: { controller.preferences.favoriteApps.contains(app.package) },
            set: { isFavorite in
                controller.preferences.favoriteApps.removeAll { $0 == app.package }
                if isFavorite { controller.preferences.favoriteApps.append(app.package) }
            }
        )
    }
}
