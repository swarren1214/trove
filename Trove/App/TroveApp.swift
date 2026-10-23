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
        // Screenshot mode borrows the settings that would show onboarding, Face ID or the blur,
        // and fills a demo household and vault before anything reads them.
        ScreenshotMode.prepareLaunch()
        #if DEBUG
        ScreenshotSeed.stage()
        #endif
        // The vault syncs in the Hearth household's iCloud: its zone registers with the
        // household before the household starts (AppRoot's task).
        TroveStore.shared.prepare()
        // Alerts use the system label color rather than the blue. Destructive buttons stay red.
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = .label
        AppLock.shared.lockIfEnabled()
        Reminders.start()
        // Trove Plus and Hearth+ (RevenueCat). Nothing is set up until the real key is in
        // AppConfig. Trove has no API client of its own: it uses the shared sign-in's token
        // while it's good (never refreshing it), for the household's plan.
        if AppConfig.revenueCatAPIKey != AppConfig.revenueCatPlaceholder {
            HearthPurchases.shared.configure(
                app: .trove,
                apiKey: AppConfig.revenueCatAPIKey,
                apiBaseURL: AppConfig.apiBaseURL,
                accessToken: { HearthAccounts.currentAccessToken() }
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                // The Hearth launch splash.
                .hearthSplash(.trove, isEnabled: !ScreenshotMode.isOn)
                .environment(router)
                .environment(lock)
                // iPhone Duo: reads the pose once for the whole window (\.hearthDuoPose below).
                .hearthDuoPose()
        }
    }
}

/// Onboarding the first time, the tabs after that, and the covers: Face ID when locked, a blur
/// with a privacy note in the app switcher (Profile › Hide in App Switcher).
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
        .tint(Brand.sky)
        .animation(.smooth, value: onboarded)
        // Hearth household invitations (the one invite for everything, the vault included).
        .hearthHouseholdInvitations()
        // Trove always works inside a household (a household of one is fine).
        .hearthHouseholdRequired(isActive: onboarded, accent: Brand.sky)
        // Trove's side of a person's page in Household: their documents.
        .environment(\.hearthPersonExtras, { person in AnyView(TrovePersonExtras(person: person)) })
        .task {
            guard !ScreenshotMode.isOn else { return }
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
                if !ScreenshotMode.isOn {
                    Task {
                        await store.syncNow()
                        await TroveSharing.update()
                    }
                }
            case .inactive:
                // Leaving Trove (the app switcher, Control Center): blur it before iOS takes the
                // switcher's snapshot. Not at launch (inactive → active), and not for the Face ID
                // prompt, which also makes the app inactive.
                if old == .active, !lock.isAuthenticating, !lock.isLocked,
                   UserDefaults.standard.bool(forKey: SettingsKey.privacyCover) {
                    CoverWindow.showPrivacy()
                }
            case .background:
                if UserDefaults.standard.bool(forKey: SettingsKey.privacyCover) {
                    CoverWindow.showPrivacy()
                }
                lock.didEnterBackground()
                store.persistNow()
            @unknown default:
                break
            }
        }
    }
}

/// Covers the whole app, sheets included, in a window above everything: the Face ID lock, or a
/// blur with a privacy note while Trove isn't the app in use.
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
        privacyWindows = makeWindows(level: .alert + 1) { PrivacyCoverController() }
    }

    /// Fades the blur away as Trove comes back.
    static func hidePrivacy() {
        let windows = privacyWindows
        privacyWindows = []
        guard !windows.isEmpty else { return }
        UIView.animate(withDuration: 0.25, animations: {
            windows.forEach { $0.alpha = 0 }
        }, completion: { _ in
            windows.forEach { $0.isHidden = true }
        })
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

/// What shows while Trove isn't the app in use: the app blurred past reading, a lock and a
/// short note. The blur is a real `UIVisualEffectView`, so it blurs the app's window beneath.
private final class PrivacyCoverController: UIViewController {
    override func loadView() {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        view = blur
        let note = UIHostingController(rootView: PrivacyNote())
        note.view.backgroundColor = .clear
        addChild(note)
        note.view.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(note.view)
        NSLayoutConstraint.activate([
            note.view.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            note.view.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
            note.view.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
            note.view.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),
        ])
        note.didMove(toParent: self)
    }
}

/// The lock and the note on the privacy blur.
private struct PrivacyNote: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Brand.sky, in: .rect(cornerRadius: 18, style: .continuous))
                .padding(.bottom, 4)
            Text("Hidden for Privacy")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Your documents stay hidden while Trove isn’t open.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
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
                .background(Brand.sky, in: .rect(cornerRadius: 22, style: .continuous))
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
        .tint(Brand.sky)
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
