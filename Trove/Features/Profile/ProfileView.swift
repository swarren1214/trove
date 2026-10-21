import AuthenticationServices
import SwiftUI
import UIKit

/// Profile, from the photo at the top right of every screen: the shared Hearth Profile with
/// Trove's reminders, the Face ID lock and exporting everything.
struct ProfileView: View {
    @Environment(AppLock.self) private var lock
    @State private var household = HearthHouseholdStore.shared
    @State private var store = TroveStore.shared
    @AppStorage(SettingsKey.faceIDLock) private var faceIDLock = true
    @AppStorage(SettingsKey.lockAfterSeconds) private var lockAfter = 60
    @AppStorage(SettingsKey.privacyCover) private var privacyCover = true
    @AppStorage(SettingsKey.expiryReminders) private var expiryReminders = true
    @AppStorage(SettingsKey.placeReminders) private var placeReminders = true
    @AppStorage(SettingsKey.onboarded) private var onboarded = true
    @State private var editingMe = false
    @AppStorage(SettingsKey.appleUserID) private var appleUserID = ""
    @AppStorage(SettingsKey.appleName) private var appleName = ""
    @AppStorage(SettingsKey.appleEmail) private var appleEmail = ""
    @State private var notificationsDenied = false

    var body: some View {
        // The shared Hearth Profile (HearthProfile.swift), with Trove's own section in the middle.
        HearthProfileView(
            app: .trove,
            profile: accountProfile,
            sync: HearthProfileSync(summary: "Your documents and scans", sharing: syncSharing) {
                TroveStore.shared.syncSnapshot
            } syncNow: {
                await TroveStore.shared.syncNow()
            },
            erase: erase
        ) {
            Section {
                ProfileAccount()
                    .hearthAccountSectionRow()
            }
        } settings: {
            troveSection
        } data: {
            // Native sharing; the PDF is made (after Face ID) only when someone picks where it
            // goes. Always free: it's your own data.
            ShareLink(item: TroveExport.everything(store: store), preview: SharePreview("Trove export")) {
                HearthProfileRow("Export Everything", systemImage: "square.and.arrow.up", value: "PDF")
            }
            .disabled(store.documents.isEmpty)
        } about: {
        }
        .refreshable {
            await household.refresh()
            await store.syncNow()
        }
        .task { notificationsDenied = await Reminders.isDenied() }
        .onChange(of: expiryReminders) { Reminders.schedule() }
        .onChange(of: placeReminders) { Reminders.schedule() }
        // Your details live in the household, for every Hearth app.
        .sheet(isPresented: $editingMe) {
            if let me = household.me {
                HearthPersonEditor(member: me, accent: Brand.sky)
            }
        }
    }

    /// Who's signed in with Apple, for the account card at the top (nil shows Sign in with Apple).
    private var accountProfile: HearthAccountProfile? {
        guard !appleUserID.isEmpty else { return nil }
        return HearthAccountProfile(name: appleName.isEmpty ? nil : appleName, email: appleEmail.isEmpty ? nil : appleEmail, method: "Signed in with Apple on this \(DeviceName.current)")
    }

    /// Trove's own settings: your info, reminders, the Face ID lock and the app-switcher blur.
    private var troveSection: some View {
        Section("Trove") {
            if household.me != nil {
                Button { editingMe = true } label: {
                    HearthProfileRow("My Info", systemImage: "person")
                }
            }
            NavigationLink { RemindersSettingsView(expiry: $expiryReminders, places: $placeReminders, denied: notificationsDenied) } label: {
                HearthProfileRow("Reminders", systemImage: "bell.badge", value: [expiryReminders, placeReminders].filter { $0 }.isEmpty ? "Off" : "On")
            }
            Toggle(isOn: Binding(
                get: { faceIDLock },
                set: { faceIDLock = $0 && lock.canLock() }
            )) {
                Label {
                    Text("Lock with \(lock.biometryName)")
                } icon: {
                    Image(systemName: "faceid").foregroundStyle(.primary)
                }
            }
            if faceIDLock {
                // A list with the checkmark on the right, not a menu (see AGENT.md).
                NavigationLink { LockAfterView(seconds: $lockAfter) } label: {
                    HearthProfileRow("Lock After", systemImage: "timer", value: LockAfterView.label(lockAfter))
                }
            }
            // Blurs Trove in the app switcher, Control Center and Notification Center.
            Toggle(isOn: $privacyCover) {
                Label {
                    Text("Hide in App Switcher")
                } icon: {
                    Image(systemName: "eye.slash").foregroundStyle(.primary)
                }
            }
            NavigationLink { AboutView() } label: {
                HearthProfileRow("About Trove", systemImage: "info.circle", value: "v\(AppConfig.version)")
            }
        }
        .tint(.primary)
    }

    /// Erase App Data, or Leave Household for a member (erasing would delete the family's
    /// documents for everyone; leaving is a member's way to clear this device).
    private var erase: HearthProfileErase {
        if store.isInFamilyVault {
            return HearthProfileErase(
                app: .trove,
                title: "Leave Household",
                question: "Leave the Household?",
                message: "You’re in your family’s documents, so erasing would delete them for everyone. Leaving the household removes them from every Hearth app on this \(DeviceName.current). Yours stay in your iCloud and come back if you leave.",
                confirm: "Leave",
                symbol: "rectangle.portrait.and.arrow.right"
            ) {
                await household.leave()
            }
        }
        return HearthProfileErase(
            app: .trove,
            title: "Erase App Data",
            question: "Erase App Data?",
            message: "This deletes every document, scan, asset and place from your devices and your iCloud\(TroveSharing.isShared ? ", and from everyone you share with" : ""). Paper originals aren’t affected. It can’t be undone."
        ) {
            store.eraseEverything()
            TroveExport.cleanUp()
            onboarded = false
            HearthProfilePresenter.shared.dismiss()
        }
    }

    /// Who the vault is shared with, once another adult has joined.
    private var syncSharing: HearthSyncSharing? {
        guard TroveSharing.isShared else { return nil }
        return HearthSyncSharing(
            label: "Your household’s adults",
            people: household.parents.map { HearthSyncSharing.Person(id: $0.id, initial: $0.initial, colorHex: $0.colorHex) }
        )
    }
}

/// Profile › Account: the shared Hearth account section. One sign-in for the Hearth apps:
/// signed in with Apple in another Hearth app on this device means signed in here too, and
/// Sign Out signs out of all of them. Everything works without it.
private struct ProfileAccount: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsKey.appleUserID) private var appleUserID = ""
    @AppStorage(SettingsKey.appleName) private var appleName = ""
    @AppStorage(SettingsKey.appleEmail) private var appleEmail = ""
    @State private var confirmsSignOut = false
    @State private var errorMessage: String?

    private var profile: HearthAccountProfile? {
        guard !appleUserID.isEmpty else { return nil }
        return HearthAccountProfile(name: appleName.isEmpty ? nil : appleName, email: appleEmail.isEmpty ? nil : appleEmail)
    }

    var body: some View {
        HearthAccountSection(
            app: .trove,
            profile: profile,
            pitch: "Sign in to use one account across your Hearth apps. Your documents stay in your iCloud either way, and everything works without it."
        ) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                    withAnimation {
                        appleUserID = credential.user
                        if let name = credential.fullName?.formatted(), !name.isEmpty { appleName = name }
                        if let email = credential.email { appleEmail = email }
                        // Apple only shares the name the first time: use another Hearth app's.
                        if appleName.isEmpty, let shared = HearthAccounts.appleID(), shared.userID == credential.user {
                            appleName = shared.fullName ?? ""
                            appleEmail = appleEmail.isEmpty ? (shared.email ?? "") : appleEmail
                        }
                    }
                    // Shared, so the other Hearth apps know who signed in (Apple sends the name
                    // and email only once).
                    HearthAccounts.saveAppleID(HearthSharedAppleID(
                        userID: credential.user,
                        fullName: appleName.isEmpty ? nil : appleName,
                        email: appleEmail.isEmpty ? nil : appleEmail,
                        updatedBy: .trove
                    ))
                case .failure(let error as ASAuthorizationError) where error.code == .canceled:
                    break
                case .failure(let error):
                    errorMessage = FriendlyError.signIn(error)
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        } onSignOut: {
            confirmsSignOut = true
        }
        .alert("Sign out of Trove?", isPresented: $confirmsSignOut) {
            Button("Sign Out", role: .destructive) {
                withAnimation {
                    appleUserID = ""
                    appleName = ""
                    appleEmail = ""
                }
                HearthAccounts.signOutEverywhere()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs out of your other Hearth apps on this \(DeviceName.current) too. Your documents stay on it and in iCloud.")
        }
        .alert("Couldn’t sign in", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { followSharedSignIn() }
        .onReceive(NotificationCenter.default.publisher(for: Hearth.didChange)) { _ in followSharedSignIn() }
    }

    /// The same person as the other Hearth apps: their Apple sign-in when there is one, and
    /// signed out when they signed out (everywhere) in another app.
    private func followSharedSignIn() {
        let sharedKey = "hearth.trove.appleIDShared"
        if let shared = HearthAccounts.appleID() {
            UserDefaults.standard.set(true, forKey: sharedKey)
            guard shared.userID != appleUserID else { return }
            appleUserID = shared.userID
            appleName = shared.fullName ?? ""
            appleEmail = shared.email ?? ""
        } else if !appleUserID.isEmpty {
            if UserDefaults.standard.bool(forKey: sharedKey) {
                // It was shared and now it's gone: signed out in another Hearth app.
                guard HearthAccounts.session() == nil else { return }
                appleUserID = ""
                appleName = ""
                appleEmail = ""
                UserDefaults.standard.set(false, forKey: sharedKey)
            } else {
                // Signed in before Trove shared its sign-in: share it now.
                HearthAccounts.saveAppleID(HearthSharedAppleID(
                    userID: appleUserID,
                    fullName: appleName.isEmpty ? nil : appleName,
                    email: appleEmail.isEmpty ? nil : appleEmail,
                    updatedBy: .trove
                ))
                if HearthAccounts.appleID()?.userID == appleUserID { UserDefaults.standard.set(true, forKey: sharedKey) }
            }
        }
    }
}

/// Profile › Reminders.
private struct RemindersSettingsView: View {
    @Binding var expiry: Bool
    @Binding var places: Bool
    var denied: Bool

    var body: some View {
        Form {
            if denied {
                Section {
                    Text("Notifications are off for Trove. Turn them on in Settings to get these reminders.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            Section {
                Toggle("Before documents expire", isOn: $expiry)
            } footer: {
                Text("Passports nine months ahead, licenses two months, registrations six weeks, insurance a month, and again a week before. Each document can have its own time.")
            }
            Section {
                Toggle("Check on originals once a year", isOn: $places)
            } footer: {
                Text("A nudge to look in the safe or the deposit box and tap Everything’s There.")
            }
        }
        .navigationTitle("Reminders")
        .onChange(of: expiry) { _, on in if on { Task { await Reminders.requestPermission() } } }
        .onChange(of: places) { _, on in if on { Task { await Reminders.requestPermission() } } }
    }
}

/// Profile › Lock After: how long Trove can be in the background before it asks again.
private struct LockAfterView: View {
    @Binding var seconds: Int

    static let choices = [0, 60, 300, 900]

    static func label(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Right away"
        case 60: "1 minute"
        case 300: "5 minutes"
        case 900: "15 minutes"
        default: "\(seconds / 60) minutes"
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Lock after", selection: $seconds) {
                    ForEach(Self.choices, id: \.self) { Text(Self.label($0)).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("How long Trove can be in the background before it asks for Face ID again.")
            }
        }
        .navigationTitle("Lock After")
    }
}

/// Profile › About Trove.
private struct AboutView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: AppConfig.version)
            }
            Section("Your privacy") {
                Text("Your documents, scans and places live on your devices and in your family’s iCloud. Their contents are end-to-end encrypted, and scans are stored as encrypted iCloud files. Nothing is sent to Hearth’s servers.")
                Text("Trove reads documents on this \(DeviceName.current) with Apple’s on-device intelligence. Numbers stay hidden until you unlock them with Face ID, and they’re never searched, logged or put in a notification.")
            }
            Section {
                Link("Privacy Policy", destination: URL(string: "https://hearthapps.com/privacy")!)
                Link("Terms of Use", destination: URL(string: "https://hearthapps.com/terms")!)
                Link("Support", destination: URL(string: "https://hearthapps.com/support")!)
            }
        }
        .navigationTitle("About Trove")
    }
}

