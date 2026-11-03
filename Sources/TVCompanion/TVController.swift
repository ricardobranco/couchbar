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

    typealias TextField = RemoteSession.TextField

    enum KeyboardPairing: Equatable {
        case idle
        case starting
        case waitingForCode
        case finishing
    }

    let preferences = Preferences()
    let mirror = MirrorSession()

    private(set) var connection: Connection = .searching
    private(set) var info: TVInfo?
    private(set) var status = TVStatus()
    private(set) var lastError: String?
    private(set) var mirrorPreview: NSImage?
    private(set) var tvTextField: TextField?
    private(set) var keyboardPairing: KeyboardPairing = .idle
    private(set) var keyboardError: String?
    private(set) var remote: RemoteSession?
    private(set) var appArtwork: [String: AppArtwork] = [:]
    private(set) var appImages: [String: NSImage] = [:]
    var isPopupVisible = false {
        didSet { if isPopupVisible && !oldValue { wakePolling() } }
    }

    private let log = Logger(subsystem: "dev.ricardobranco.tvcompanion", category: "connection")
    private var client: TVClient?
    private var pollTask: Task<Void, Never>?
    private var pendingVolume: Int?
    private var remoteIdentity: RemoteIdentity?
    private var pairing: RemotePairing?
    private var isConnectingRemote = false
    // A certificate the TV already trusts (paired earlier, or the setting was lost) connects without
    // pairing again, so the first connection is always tried once.
    private var hasProbedKeyboard = false
    private var artworkTask: Task<Void, Never>?

    private static let artworkDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "TV Companion/apps")

    private static let remoteDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "TV Companion/remote")

    init(autoStart: Bool = true) {
        if autoStart { start() }
    }

    #if DEBUG
    static var previewArtworkDirectory: URL?

    static func preview(connection: Connection = .connected, info: TVInfo?, status: TVStatus = TVStatus(), mirroring: Bool = false, mirrorPreview: NSImage? = nil, error: String? = nil) -> TVController {
        let controller = TVController(autoStart: false)
        controller.connection = connection
        controller.info = info
        controller.status = status
        controller.lastError = error
        let directory = previewArtworkDirectory
        for file in directory.flatMap({ try? FileManager.default.contentsOfDirectory(atPath: $0.path) }) ?? [] where file.hasSuffix(".json") {
            if let directory, let data = try? Data(contentsOf: directory.appending(path: file)),
               let artwork = try? JSONDecoder().decode(AppArtwork.self, from: data) {
                controller.apply(artwork, for: String(file.dropLast(5)), from: directory)
            }
        }
        if mirroring { controller.mirror.simulateRunning() }
        controller.mirrorPreview = mirrorPreview
        return controller
    }
    #endif

    var tvName: String { info?.name ?? "TV" }
    var isConnected: Bool { connection == .connected }
    var isOn: Bool { status.power?.isOn ?? false }
    var isKeyboardConnected: Bool { remote != nil }

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
        disconnectRemote()
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
            if remote == nil, !isConnectingRemote, preferences.keyboardPaired || !hasProbedKeyboard {
                hasProbedKeyboard = true
                Task { await connectRemote() }
            }
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
            loadArtwork(client: client, apps: info.apps)
            log.info("Connected to \(info.name, privacy: .public) as \(serial, privacy: .public)")
        } catch {
            log.error("Connection failed: \(error.localizedDescription, privacy: .public)")
            connection = .unavailable(error.localizedDescription)
        }
    }

    func name(for app: TVApp) -> String {
        appArtwork[app.package]?.label ?? app.name
    }

    private func loadArtwork(client: TVClient, apps: [TVApp]) {
        guard let loader = AppArtworkLoader(adb: client.adb, serial: client.serial, cacheDirectory: Self.artworkDirectory) else { return }
        let favorites = Set(preferences.favoriteApps)
        let packages = apps.map(\.package).sorted { favorites.contains($0) && !favorites.contains($1) }
        artworkTask?.cancel()
        artworkTask = Task.detached { [weak self] in
            await loader.load(packages) { [weak self] package, artwork in
                await self?.apply(artwork, for: package)
            }
        }
    }

    private func apply(_ artwork: AppArtwork, for package: String, from directory: URL = artworkDirectory) {
        appArtwork[package] = artwork
        appImages[package] = artwork.imageFile.flatMap { NSImage(contentsOf: directory.appending(path: $0)) }
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

    // MARK: Keyboard

    func setTVText(_ text: String) {
        remote?.setText(text)
    }

    func submitTVText() {
        remote?.press(RemoteSession.enterKey)
    }

    func startKeyboardPairing() {
        guard let host = info?.ipAddress else {
            keyboardError = "The TV's network address is not known yet. Connect to the TV first."
            return
        }
        keyboardError = nil
        keyboardPairing = .starting
        Task {
            do {
                let pairing = RemotePairing(host: host, identity: try await loadRemoteIdentity(), clientName: "TV Companion")
                self.pairing = pairing
                try await pairing.start()
                keyboardPairing = .waitingForCode
            } catch {
                failPairing(error)
            }
        }
    }

    func finishKeyboardPairing(code: String) {
        guard let pairing else { return }
        keyboardError = nil
        keyboardPairing = .finishing
        Task {
            do {
                try await pairing.finish(code: code.trimmingCharacters(in: .whitespaces))
                self.pairing = nil
                keyboardPairing = .idle
                preferences.keyboardPaired = true
                await connectRemote()
            } catch RemoteError.invalidCode where self.pairing != nil {
                keyboardError = RemoteError.invalidCode.localizedDescription
                keyboardPairing = .waitingForCode
            } catch {
                failPairing(error)
            }
        }
    }

    func cancelKeyboardPairing() {
        pairing?.cancel()
        pairing = nil
        keyboardPairing = .idle
    }

    func unpairKeyboard() {
        preferences.keyboardPaired = false
        disconnectRemote()
        remoteIdentity = nil
        try? FileManager.default.removeItem(at: Self.remoteDirectory)
    }

    private func failPairing(_ error: Error) {
        pairing?.cancel()
        pairing = nil
        keyboardPairing = .idle
        keyboardError = error.localizedDescription
    }

    private func connectRemote() async {
        guard let host = info?.ipAddress, !isConnectingRemote else { return }
        guard preferences.keyboardPaired || FileManager.default.fileExists(atPath: Self.remoteDirectory.appending(path: "identity.p12").path) else { return }
        isConnectingRemote = true
        defer { isConnectingRemote = false }
        do {
            let session = RemoteSession(host: host, identity: try await loadRemoteIdentity())
            session.onTextField = { [weak self] in self?.tvTextField = $0 }
            session.onClose = { [weak self, weak session] in
                guard let self, let session, self.remote === session else { return }
                self.remote = nil
                self.tvTextField = nil
            }
            try await session.connect()
            remote = session
            preferences.keyboardPaired = true
        } catch {
            log.error("Keyboard connection failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func disconnectRemote() {
        remote?.close()
        remote = nil
        tvTextField = nil
    }

    private func loadRemoteIdentity() async throws -> RemoteIdentity {
        if let remoteIdentity { return remoteIdentity }
        let identity = try await RemoteIdentity.loadOrCreate(in: Self.remoteDirectory)
        remoteIdentity = identity
        return identity
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
