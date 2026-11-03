import AppKit
import Observation
import os
import TVCompanionCore

@Observable
@MainActor
final class TVController {
    enum Connection: Equatable {
        case searching
        case connected
        case unavailable(String)
    }

    let preferences = Preferences()
    let mirror = MirrorSession()

    private(set) var connection: Connection = .searching
    private(set) var info: TVInfo?
    private(set) var status = TVStatus()
    private(set) var lastError: String?
    private(set) var mirrorPreview: NSImage?
    var isPopupVisible = false {
        didSet { if isPopupVisible && !oldValue { wakePolling() } }
    }

    private let log = Logger(subsystem: "dev.ricardobranco.tvcompanion", category: "connection")
    private var client: TVClient?
    private var pollTask: Task<Void, Never>?
    private var pendingVolume: Int?

    init(autoStart: Bool = true) {
        if autoStart { start() }
    }

    #if DEBUG
    static func preview(connection: Connection = .connected, info: TVInfo?, status: TVStatus = TVStatus(), mirroring: Bool = false, mirrorPreview: NSImage? = nil, error: String? = nil) -> TVController {
        let controller = TVController(autoStart: false)
        controller.connection = connection
        controller.info = info
        controller.status = status
        controller.lastError = error
        if mirroring { controller.mirror.simulateRunning() }
        controller.mirrorPreview = mirrorPreview
        return controller
    }
    #endif

    var tvName: String { info?.name ?? "TV" }
    var isConnected: Bool { connection == .connected }
    var isOn: Bool { status.power?.isOn ?? false }

    var inputs: [TVInput] { info?.inputs ?? [] }

    var favoriteApps: [TVApp] {
        let installed = Set(info?.apps.map(\.package) ?? [])
        return preferences.favoriteApps.filter(installed.contains).map(TVApp.init)
    }

    var displayedVolume: Int? { pendingVolume ?? status.volume?.current }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func reconnect() {
        client = nil
        info = nil
        connection = .searching
        wakePolling()
    }

    private func wakePolling() {
        pollTask?.cancel()
        pollTask = nil
        start()
    }

    private var pollInterval: Duration {
        switch connection {
        case .connected: isPopupVisible ? .seconds(2) : .seconds(20)
        case .searching, .unavailable: isPopupVisible ? .seconds(5) : .seconds(30)
        }
    }

    private func tick() async {
        if client == nil { await connect() }
        guard let client else { return }
        do {
            let newStatus = try await client.status()
            if !Task.isCancelled { status = newStatus }
        } catch {
            log.error("Status failed: \(error.localizedDescription, privacy: .public)")
            self.client = nil
            connection = .unavailable(error.localizedDescription)
        }
    }

    private func connect() async {
        guard let adb = ADB.locate(override: preferences.adbPath) else {
            connection = .unavailable(ADBError.notFound.localizedDescription)
            return
        }
        do {
            let resolver = DeviceResolver(adb: adb)
            guard let serial = try await resolver.resolve(serialNumber: preferences.serialNumber, manualAddress: preferences.manualAddress) else {
                log.error("No TV found")
                connection = .unavailable("No TV found. Check that wireless debugging is on and the Mac is on the same network.")
                return
            }
            let client = TVClient(adb: adb, serial: serial)
            let info = try await client.info()
            self.client = client
            self.info = info
            preferences.serialNumber = info.serialNumber
            if let mac = info.macAddress { preferences.macAddress = mac }
            connection = .connected
            log.info("Connected to \(info.name, privacy: .public) as \(serial, privacy: .public)")
        } catch {
            log.error("Connection failed: \(error.localizedDescription, privacy: .public)")
            connection = .unavailable(error.localizedDescription)
        }
    }

    // MARK: Actions

    func press(_ key: TVKey) {
        perform { try await $0.press(key) }
    }

    func setVolume(_ target: Int) {
        guard target != status.volume?.current else {
            pendingVolume = nil
            return
        }
        pendingVolume = target
        perform { client in
            try await client.setVolume(target)
            await self.refreshStatus()
            self.pendingVolume = nil
        }
    }

    func stepVolume(up: Bool) {
        perform { client in
            try await client.press(up ? .volumeUp : .volumeDown)
            try? await Task.sleep(for: .milliseconds(300))
            await self.refreshStatus()
        }
    }

    func previewVolume(_ value: Int) {
        pendingVolume = value
    }

    func launch(_ app: TVApp) {
        perform { try await $0.launch(app.package) }
    }

    func switchInput(_ input: TVInput) {
        perform { try await $0.switchInput(input) }
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        perform { try await $0.sendText(text) }
    }

    func togglePower() {
        if isConnected {
            perform { client in
                try await client.press(self.isOn ? .sleep : .wakeUp)
                try? await Task.sleep(for: .seconds(1))
                await self.refreshStatus()
            }
        } else if let mac = preferences.macAddress {
            do {
                try WakeOnLAN.send(to: mac)
                reconnect()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    var canWake: Bool { !isConnected && preferences.macAddress != nil }

    func toggleMirroring() {
        if mirror.isRunning {
            mirror.stop()
            return
        }
        guard let client else { return }
        guard let scrcpy = Scrcpy.locate(override: preferences.scrcpyPath) else {
            lastError = "scrcpy was not found. Install it with `brew install scrcpy` or set its path in Settings."
            return
        }
        mirrorPreview = nil
        mirror.start(scrcpy: scrcpy, adb: client.adb, serial: client.serial, title: tvName, options: preferences.mirror)
    }

    func refreshMirrorPreview() async {
        guard let client, let data = try? await client.screenshot() else { return }
        mirrorPreview = NSImage(data: data)
    }

    func saveScreenshot() {
        perform { client in
            let data = try await client.screenshot()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                .appending(path: "TV Screenshot \(formatter.string(from: .now)).png")
            try data.write(to: url)
            if let image = NSImage(data: data) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
        }
    }

    func clearError() {
        lastError = nil
    }

    private func refreshStatus() async {
        guard let client, let newStatus = try? await client.status() else { return }
        status = newStatus
    }

    private func perform(_ action: @escaping @MainActor (TVClient) async throws -> Void) {
        guard let client else {
            lastError = "The TV is not connected."
            return
        }
        Task {
            do {
                try await action(client)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                pendingVolume = nil
            }
        }
    }
}
