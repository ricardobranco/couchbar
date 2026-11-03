import Foundation

public struct TVApp: Sendable, Hashable, Identifiable {
    public let package: String
    public let name: String
    public let symbol: String

    public var id: String { package }

    public init(package: String) {
        self.package = package
        let known = Self.catalog[package]
        name = known?.name ?? Self.fallbackName(for: package)
        symbol = known?.symbol ?? "app"
    }

    public static let defaultFavorites = [
        "com.netflix.ninja",
        "com.google.android.youtube.tv",
        "com.amazon.amazonvideo.livingroom",
        "com.disney.disneyplus",
        "com.wbd.stream",
        "com.apple.atve.androidtv.appletv",
        "com.spotify.tv.android",
        "com.plexapp.android",
        "com.vodafone.vtv.atv.pt",
        "pt.rtp.play",
    ]

    static let hidden: Set<String> = [
        "com.android.vending",
        "com.tcl.dashboard",
        "com.tcl.suspension",
        "com.tcl.t_solo",
        "com.tcl.tv",
    ]

    public static func isUserFacing(_ package: String) -> Bool {
        !hidden.contains(package)
    }

    private static let catalog: [String: (name: String, symbol: String)] = [
        "com.netflix.ninja": ("Netflix", "n.square.fill"),
        "com.google.android.youtube.tv": ("YouTube", "play.rectangle.fill"),
        "com.amazon.amazonvideo.livingroom": ("Prime Video", "play.tv.fill"),
        "com.disney.disneyplus": ("Disney+", "sparkles.tv.fill"),
        "com.wbd.stream": ("Max", "m.square.fill"),
        "com.apple.atve.androidtv.appletv": ("Apple TV", "appletv.fill"),
        "com.spotify.tv.android": ("Spotify", "music.note"),
        "com.plexapp.android": ("Plex", "play.circle.fill"),
        "com.vodafone.vtv.atv.pt": ("Vodafone TV", "antenna.radiowaves.left.and.right"),
        "pt.rtp.play": ("RTP Play", "play.square.stack.fill"),
        "pt.iol.tviplayer.androidtv": ("TVI Player", "play.square.stack"),
        "com.impresa.opta": ("Opto", "play.square"),
        "com.nordvpn.android": ("NordVPN", "lock.shield.fill"),
        "com.android.tv.settings": ("Settings", "gearshape.fill"),
        "dev.vodik7.tvquickactions": ("Quick Actions", "bolt.fill"),
    ]

    private static func fallbackName(for package: String) -> String {
        let last = package.split(separator: ".").last { !["tv", "android", "androidtv", "app"].contains($0) }
        return (last.map(String.init) ?? package).capitalized
    }
}
