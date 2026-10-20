import Foundation
import LocalAuthentication
import Observation

/// Profile › Lock with Face ID (on by default). When it's on, Trove covers itself when it goes
/// to the background and asks for Face ID (or the passcode) to come back, after the chosen grace
/// period.
@Observable
final class AppLock {
    static let shared = AppLock()

    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    @ObservationIgnored private var backgroundedAt: Date?

    /// On, and past the welcome screen (nothing to protect before that).
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.faceIDLock) && UserDefaults.standard.bool(forKey: SettingsKey.onboarded)
    }
    private var graceSeconds: Double { Double(UserDefaults.standard.integer(forKey: SettingsKey.lockAfterSeconds)) }

    /// "Face ID", "Touch ID" or "Passcode", for labels.
    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// At launch.
    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    /// When the app goes to the background: remember when, to apply the grace period.
    func didEnterBackground() {
        backgroundedAt = .now
        if isEnabled && graceSeconds <= 0 { isLocked = true }
    }

    /// When it comes back: lock if it was away longer than the grace period.
    func willEnterForeground() {
        guard isEnabled, let backgroundedAt else { return }
        if Date.now.timeIntervalSince(backgroundedAt) >= graceSeconds { isLocked = true }
        self.backgroundedAt = nil
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your documents")
            if ok { isLocked = false }
        } catch {
            // Stay locked; the lock screen offers to try again.
        }
    }

    /// Checks that this device can authenticate before turning the lock on.
    func canLock() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Face ID (or the passcode) for one sensitive thing, like showing a document number. Always
    /// asked, even with the app lock off.
    static func confirm(_ reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No passcode on this device: nothing to check against.
            return true
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
