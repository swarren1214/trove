import AuthenticationServices
import CloudKit
import Foundation
import os

/// Words a person can act on for an error, instead of the system's raw message. The raw error
/// still goes to the log. Cancels should stay quiet: check for them before calling.
enum FriendlyError {
    private static let log = Logger(subsystem: "com.stephenwarren.trove", category: "errors")

    /// Sign in with Apple didn't finish (a cancel isn't an error; leave it out).
    static func signIn(_ error: Error) -> String {
        log.error("Sign in with Apple failed: \(String(describing: error), privacy: .public)")
        if let auth = error as? ASAuthorizationError {
            switch auth.code {
            case .notHandled, .invalidResponse:
                return "Apple didn’t finish signing you in. Try again in a moment."
            case .notInteractive:
                return "Sign in with Apple needs you to be on this screen. Try again."
            default:
                break
            }
        }
        if isOffline(error) {
            return "You’re offline. Connect to the internet and try again."
        }
        return "Trove couldn’t sign you in with Apple. Check that you’re signed in to your Apple Account in Settings, then try again."
    }

    /// No internet, from URL or CloudKit errors.
    static func isOffline(_ error: Error) -> Bool {
        if let url = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(url.code) { return true }
        if let ck = error as? CKError, [.networkUnavailable, .networkFailure].contains(ck.code) { return true }
        return false
    }
}
