import SwiftUI
import UIKit

/// Keys for settings stored with @AppStorage. Keep every key here so views stay in sync.
nonisolated enum SettingsKey {
    /// Onboarding has been finished.
    static let onboarded = "onboarding.done"
    /// Ask for Face ID when Trove opens (Profile › Lock with Face ID). On by default: Trove holds
    /// the most sensitive things in any Hearth app.
    static let faceIDLock = "privacy.faceIDLock"
    /// Lock again after this many seconds in the background (0 = right away).
    static let lockAfterSeconds = "privacy.lockAfterSeconds"
    /// Blur Trove and show a privacy note whenever it isn't the app in use: the app switcher,
    /// Control Center, Notification Center (Profile › Hide in App Switcher). On by default.
    static let privacyCover = "privacy.cover"
    /// Local notifications before documents expire (Profile › Reminders).
    static let expiryReminders = "reminders.expiry"
    /// A yearly nudge to check that each place still holds its originals.
    static let placeReminders = "reminders.places"
    /// The Sign in with Apple user on this device, when they chose to sign in.
    static let appleUserID = "account.appleUserID"
    static let appleName = "account.appleName"
    static let appleEmail = "account.appleEmail"
    /// The kinds of documents picked in onboarding ("What should Trove keep?"), as
    /// `DocumentType` raw values joined by commas: Home's "Start with" list. Empty uses the usual ones.
    static let firstDocuments = "onboarding.firstDocuments"

    /// Defaults for settings that start on.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            faceIDLock: true,
            lockAfterSeconds: 60,
            privacyCover: true,
            expiryReminders: true,
            placeReminders: true,
        ])
    }
}

/// Trove's colors: a bright sky blue (#38C2E9). It fills buttons, the header and icon squares.
/// It's too light for small text on white, so text and icons in the app's color use `ink`.
nonisolated enum Brand {
    /// Buttons, the selected tab, the confirm button on sheets.
    static let sky = Color(hex: 0x38C2E9)
    /// Top of the header gradient: a deeper blue, so the white title and icons read on it.
    static let skyDeep = Color(hex: 0x1C9DC4)
    /// Middle of the header gradient.
    static let skyMid = Color(hex: 0x38C2E9)
    /// Text and icons in the app's color: a deep blue on light (4.9:1 on white), a pale blue on dark.
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x6FD6F2) : UIColor(hex: 0x0F7A9C)
    })
    /// The soft blue behind icons.
    static let tint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x38C2E9).withAlphaComponent(0.28) : UIColor(hex: 0xDFF4FB)
    })
    static let secondaryText = Color(.secondaryLabel)
}

/// How urgent something is: soon (amber) or now (red). Each has a pale fill and a readable ink
/// in both appearances.
nonisolated enum Urgency: Int, Comparable, Sendable {
    case calm, soon, now

    static func < (a: Urgency, b: Urgency) -> Bool { a.rawValue < b.rawValue }

    var ink: Color {
        switch self {
        case .calm: Color(.secondaryLabel)
        case .soon: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xFFB45C) : UIColor(hex: 0x9A5B00) })
        case .now: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xFF7A70) : UIColor(hex: 0xB3261E) })
        }
    }

    var fill: Color {
        switch self {
        case .calm: Color(.tertiarySystemFill)
        case .soon: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xFFB45C).withAlphaComponent(0.18) : UIColor(hex: 0xFFEFD9) })
        case .now: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xFF7A70).withAlphaComponent(0.18) : UIColor(hex: 0xFDE4E2) })
        }
    }
}

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// "iPhone" or "iPad", for sentences.
enum DeviceName {
    static var current: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
}
