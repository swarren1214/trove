import CloudKit
import SwiftUI
import UIKit

@main
struct TroveApp: App {
    @UIApplicationDelegateAdaptor(TroveAppDelegate.self) private var appDelegate
    @State private var router = AppRouter.shared
    @State private var lock = AppLock.shared

    init() {
        SettingsKey.registerDefaults()
        // The vault syncs in the Hearth household's iCloud: its zone registers with the
        // household before the household starts (AppRoot's task).
        TroveStore.shared.prepare()
        // Alerts use the system label color rather than the jade. Destructive buttons stay red.
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = .label
        AppLock.shared.lockIfEnabled()
        Reminders.start()
        // Trove Plus and Hearth+ (RevenueCat). Nothing is set up until the real key is in
        // AppConfig. Trove has no Hearth server account, so there's no access token.
        if AppConfig.revenueCatAPIKey != AppConfig.revenueCatPlaceholder {
            HearthPurchases.shared.configure(app: .trove, apiKey: AppConfig.revenueCatAPIKey, apiBaseURL: AppConfig.apiBaseURL)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                // The Hearth launch splash.
                .hearthSplash(.trove)
                .environment(router)
                .environment(lock)
        }
    }
}

/// The welcome screen the first time, the tabs after that, and the covers: Face ID when locked,
/// a blur in the app switcher.
struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Environment(AppLock.self) private var lock
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @State private var store = TroveStore.shared
    /// The Hearth household: the same family in every Hearth app. Trove always has one.
    @State private var family = HearthHouseholdStore.shared

    var body: some View {
        Group {
            if onboarded {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
        .tint(Brand.jade)
        .animation(.smooth, value: onboarded)
        // Hearth household invitations (the one invite for everything, the vault included).
        .hearthHouseholdInvitations()
        // Trove always works inside a household (a household of one is fine).
        .hearthHouseholdRequired(isActive: onboarded, accent: Brand.jade)
        // Trove's side of a person's page in Household: their documents.
        .environment(\.hearthPersonExtras, { person in AnyView(TrovePersonExtras(person: person)) })
        .task {
            family.start(app: .trove)
            store.refreshLocation()
            await TroveSharing.update()
            await Reminders.refresh()
        }
        // Share the vault with the household's adults, or join the family's.
        .onChange(of: family.mode) {
            store.refreshLocation()
            Task { await TroveSharing.update() }
        }
        .onChange(of: family.exists) { Task { await TroveSharing.update() } }
        .onChange(of: family.participants.count) { Task { await TroveSharing.update() } }
        .onChange(of: family.info?.appShareURLs) { Task { await TroveSharing.update() } }
        // Reminders follow every change, here or from iCloud.
        .onChange(of: store.state) { Reminders.schedule() }
        .onOpenURL { url in
            // trove://document/<id>
            guard url.scheme == "trove" else { return }
            let id = url.lastPathComponent
            switch url.host() {
            case "document": router.open(.document(id))
            case "asset": router.open(.asset(id))
            case "place": router.open(.place(id))
            default: router.tab = .home
            }
        }
        // The lock cover gets its own window, so it hides open sheets too.
        .onChange(of: lock.isLocked, initial: true) { _, locked in
            if locked { CoverWindow.showLock(lock) } else { CoverWindow.hideLock() }
        }
        .onChange(of: scenePhase) { old, phase in
            switch phase {
            case .active:
                CoverWindow.hidePrivacy()
                if old == .background {
                    lock.willEnterForeground()
                    Task { await lock.unlock() }
                }
                Task {
                    await store.syncNow()
                    await TroveSharing.update()
                }
            case .inactive:
                // The app switcher's snapshot shows a cover, never a document.
                CoverWindow.showPrivacy()
            case .background:
                CoverWindow.showPrivacy()
                lock.didEnterBackground()
                store.persistNow()
            @unknown default:
                break
            }
        }
    }
}

/// Covers the whole app, sheets included, in a window above everything: the Face ID lock, or a
/// plain cover while the app is in the app switcher.
enum CoverWindow {
    /// One cover per window scene, so every iPad window (Split View, Stage Manager) is hidden.
    private static var lockWindows: [UIWindow] = []
    private static var privacyWindows: [UIWindow] = []

    static func showLock(_ lock: AppLock) {
        guard lockWindows.isEmpty else { return }
        lockWindows = makeWindows(level: .alert + 2) { UIHostingController(rootView: LockView().environment(lock)) }
    }

    static func hideLock() {
        lockWindows.forEach { $0.isHidden = true }
        lockWindows = []
    }

    static func showPrivacy() {
        guard privacyWindows.isEmpty else { return }
        privacyWindows = makeWindows(level: .alert + 1) { UIHostingController(rootView: PrivacyCover()) }
    }

    static func hidePrivacy() {
        privacyWindows.forEach { $0.isHidden = true }
        privacyWindows = []
    }

    private static func makeWindows(level: UIWindow.Level, controller: () -> UIViewController) -> [UIWindow] {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.map { scene in
            let cover = UIWindow(windowScene: scene)
            cover.rootViewController = controller()
            cover.windowLevel = level
            cover.isHidden = false
            return cover
        }
    }
}

/// What the app switcher shows: the jade, the Trove mark, nothing else.
private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Brand.jadeDeep.ignoresSafeArea()
            Image(systemName: "archivebox.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)
        }
    }
}

/// The cover while Trove is locked (Profile › Lock with Face ID).
struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "archivebox.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(Brand.jade, in: .rect(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text("Trove is locked")
                .font(.largeTitle.bold())
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            Text("Unlock to see your documents.")
                .foregroundStyle(.secondary)
            Spacer()
            PrimaryButton(title: "Unlock with \(lock.biometryName)", systemImage: "faceid") {
                Task { await lock.unlock() }
            }
            .disabled(lock.isAuthenticating)
            .frame(maxWidth: 460)
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .tint(Brand.jade)
        .task { await lock.unlock() }
    }
}

/// Push notifications (CKSyncEngine hears about changes in iCloud through them) and the scene
/// delegate that receives Hearth household invitations. The vault needs no invitation of its
/// own: it's shared with the household automatically (`TroveSharing`).
final class TroveAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = TroveSceneDelegate.self
        return configuration
    }
}

/// Tapping a household invitation (in Messages or Mail) lands here, whether Trove was running
/// or not.
final class TroveSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata, HearthHouseholdStore.handles(metadata) {
            HearthHouseholdStore.shared.receive(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        if HearthHouseholdStore.handles(cloudKitShareMetadata) {
            HearthHouseholdStore.shared.receive(cloudKitShareMetadata)
        }
    }
}
