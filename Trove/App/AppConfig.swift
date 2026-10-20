import Foundation

/// App-wide settings.
enum AppConfig {
    static let appName = "Trove"

    /// RevenueCat's public Apple key for Trove (appl_…), for Trove Plus and Hearth+. Until it's
    /// filled in, purchases aren't set up and the paid features stay locked.
    nonisolated static let revenueCatAPIKey = "REVENUECAT_PUBLIC_KEY"
    nonisolated static let revenueCatPlaceholder = "REVENUECAT_PUBLIC_KEY"
    nonisolated static let apiBaseURL = URL(string: "https://api.hearthapps.com")!

    /// Assets anyone can add for free. Trove Plus (or Hearth+) has no limit. Documents, scans,
    /// places, reminders and export are always free.
    static let freeAssetLimit = 3

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }
}

/// The paid features, as the paywall and the locked cards name them.
enum TrovePlus {
    static let assets = HearthPaywallFeature(
        "Unlimited assets",
        detail: "Add every home, vehicle and valuable you own, each with its own documents.",
        symbol: "square.grid.2x2"
    )
    static let emergencyPacket = HearthPaywallFeature(
        "Emergency packet",
        detail: "A list of what your family has and where each original is kept, ready to hand to someone you trust.",
        symbol: "cross.case"
    )
}
