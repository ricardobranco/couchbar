import Foundation
import Observation
import CouchbarCore

@Observable
@MainActor
final class Preferences {
    private let defaults = UserDefaults.standard

    var serialNumber: String? { didSet { defaults.set(serialNumber, forKey: "serialNumber") } }
    var macAddress: String? { didSet { defaults.set(macAddress, forKey: "macAddress") } }
    var manualAddress: String { didSet { defaults.set(manualAddress, forKey: "manualAddress") } }
    var adbPath: String { didSet { defaults.set(adbPath, forKey: "adbPath") } }
    var scrcpyPath: String { didSet { defaults.set(scrcpyPath, forKey: "scrcpyPath") } }
    var favoriteApps: [String] { didSet { defaults.set(favoriteApps, forKey: "favoriteApps") } }
    var inputNames: [String: String] { didSet { defaults.set(inputNames, forKey: "inputNames") } }
    var mirror: MirrorOptions { didSet { saveMirror() } }
    var keyboardPaired: Bool { didSet { defaults.set(keyboardPaired, forKey: "keyboardPaired") } }

    init() {
        serialNumber = defaults.string(forKey: "serialNumber")
        macAddress = defaults.string(forKey: "macAddress")
        manualAddress = defaults.string(forKey: "manualAddress") ?? ""
        adbPath = defaults.string(forKey: "adbPath") ?? ""
        scrcpyPath = defaults.string(forKey: "scrcpyPath") ?? ""
        favoriteApps = defaults.stringArray(forKey: "favoriteApps") ?? TVApp.defaultFavorites
        inputNames = defaults.dictionary(forKey: "inputNames") as? [String: String] ?? [:]
        keyboardPaired = defaults.bool(forKey: "keyboardPaired")

        var mirror = MirrorOptions()
        if defaults.object(forKey: "mirror.maxSize") != nil {
            mirror.maxSize = defaults.integer(forKey: "mirror.maxSize")
            mirror.bitRateMbps = defaults.integer(forKey: "mirror.bitRateMbps")
            mirror.maxFPS = defaults.integer(forKey: "mirror.maxFPS")
            mirror.forwardAudio = defaults.bool(forKey: "mirror.forwardAudio")
            mirror.allowControl = defaults.bool(forKey: "mirror.allowControl")
            mirror.alwaysOnTop = defaults.bool(forKey: "mirror.alwaysOnTop")
        }
        self.mirror = mirror
    }

    func name(for input: TVInput) -> String {
        inputNames[input.id].flatMap { $0.isEmpty ? nil : $0 } ?? input.defaultName
    }

    private func saveMirror() {
        defaults.set(mirror.maxSize, forKey: "mirror.maxSize")
        defaults.set(mirror.bitRateMbps, forKey: "mirror.bitRateMbps")
        defaults.set(mirror.maxFPS, forKey: "mirror.maxFPS")
        defaults.set(mirror.forwardAudio, forKey: "mirror.forwardAudio")
        defaults.set(mirror.allowControl, forKey: "mirror.allowControl")
        defaults.set(mirror.alwaysOnTop, forKey: "mirror.alwaysOnTop")
    }
}
