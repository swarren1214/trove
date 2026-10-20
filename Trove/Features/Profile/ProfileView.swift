import AuthenticationServices
import SwiftUI
import UIKit

/// Profile, from the avatar at the top right of every screen: who you are, the Hearth account,
/// Trove Plus, iCloud sync, Household, reminders, the Face ID lock, exporting everything, the
/// other Hearth apps, and erasing.
struct ProfileView: View {
    @Environment(AppLock.self) private var lock
    @State private var household = HearthHouseholdStore.shared
    @State private var store = TroveStore.shared
    @AppStorage(SettingsKey.faceIDLock) private var faceIDLock = true
    @AppStorage(SettingsKey.lockAfterSeconds) private var lockAfter = 60
    @AppStorage(SettingsKey.expiryReminders) private var expiryReminders = true
    @AppStorage(SettingsKey.placeReminders) private var placeReminders = true
    @AppStorage(SettingsKey.onboarded) private var onboarded = true
    @State private var editingMe = false
    @State private var confirmsErase = false
    @State private var notificationsDenied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                ProfileAccount()

                // Get Hearth+, or manage the plan.
                HearthMembershipRow()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 54)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))

                HearthSyncCard(app: .trove, snapshot: store.syncSnapshot, summary: "Your documents and scans", sharing: syncSharing) {
                    await store.syncNow()
                }

                VStack(spacing: 0) {
                    if household.me != nil {
                        Button { editingMe = true } label: {
                            ProfileRow(symbol: "person", color: Color(hex: 0x3D3D3D), title: "My info", value: "")
                        }
                        Divider().padding(.leading, 60)
                    }
                    // The people (added and edited only here), inviting the family, and who's
                    // using this device. The vault is shared with the household's adults.
                    NavigationLink { HearthHouseholdView(accent: Brand.sky) } label: {
                        ProfileRow(
                            symbol: HearthHouseholdLabel.symbol,
                            color: Color(hex: 0x7B61FF),
                            title: HearthHouseholdLabel.title,
                            value: household.exists ? (household.people.count == 1 ? "1 person" : "\(household.people.count) people") : "Set up"
                        )
                    }
                    Divider().padding(.leading, 60)
                    NavigationLink { RemindersSettingsView(expiry: $expiryReminders, places: $placeReminders, denied: notificationsDenied) } label: {
                        ProfileRow(symbol: "bell.badge", color: Color(hex: 0xC25E00), title: "Reminders", value: [expiryReminders, placeReminders].filter { $0 }.isEmpty ? "Off" : "On")
                    }
                    Divider().padding(.leading, 60)
                    HStack(spacing: 12) {
                        ProfileIcon(symbol: "faceid", color: Color(hex: 0x3D3D3D))
                        Toggle("Lock with \(lock.biometryName)", isOn: Binding(
                            get: { faceIDLock },
                            set: { faceIDLock = $0 && lock.canLock() }
                        ))
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    if faceIDLock {
                        Divider().padding(.leading, 60)
                        // A list with the checkmark on the right, not a menu (see AGENT.md).
                        NavigationLink { LockAfterView(seconds: $lockAfter) } label: {
                            ProfileRow(symbol: "timer", color: Color(hex: 0x5B5B60), title: "Lock after", value: LockAfterView.label(lockAfter))
                        }
                    }
                    Divider().padding(.leading, 60)
                    // Native sharing; the PDF is made (after Face ID) only when someone picks where
                    // it goes. Always free: it's your own data.
                    ShareLink(item: TroveExport.everything(store: store), preview: SharePreview("Trove export")) {
                        ProfileRow(symbol: "square.and.arrow.up", color: Brand.sky, title: "Export Everything", value: "PDF")
                    }
                    .disabled(store.documents.isEmpty)
                    Divider().padding(.leading, 60)
                    NavigationLink { AboutView() } label: {
                        ProfileRow(symbol: "info.circle", color: Brand.sky, title: "About Trove", value: "v\(AppConfig.version)")
                    }
                }
                .buttonStyle(.plain)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))

                NavigationLink { HearthAppsView(current: .trove) } label: {
                    HStack(spacing: 12) {
                        HearthAppsRowLabel(current: .trove)
                        Spacer(minLength: 8)
                        Chevron()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 54)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))

                Button(role: .destructive) { confirmsErase = true } label: {
                    Label(store.isInFamilyVault ? "Leave Household" : "Erase App Data", systemImage: store.isInFamilyVault ? "rectangle.portrait.and.arrow.right" : "trash")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: TroveScreen<EmptyView>.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) { HeaderGradient() }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Profile")
        .refreshable {
            await household.refresh()
            await store.syncNow()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
            if household.me != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editingMe = true } label: {
                        Text("Edit").foregroundStyle(.white)
                    }
                }
            }
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
        .alert(store.isInFamilyVault ? "Leave the Household?" : "Erase App Data?", isPresented: $confirmsErase) {
            Button("Cancel", role: .cancel) {}
            if store.isInFamilyVault {
                // Erasing would delete the family's documents for everyone; leaving the
                // household is a member's way to clear this device.
                Button("Leave", role: .destructive) {
                    Task { await household.leave() }
                }
            } else {
                Button("Erase", role: .destructive) {
                    store.eraseEverything()
                    TroveExport.cleanUp()
                    onboarded = false
                }
            }
        } message: {
            if store.isInFamilyVault {
                Text("You’re in your family’s documents, so erasing would delete them for everyone. Leaving the household removes them from every Hearth app on this \(DeviceName.current). Yours stay in your iCloud and come back if you leave.")
            } else {
                Text("This deletes every document, scan, asset and place from your devices and your iCloud\(TroveSharing.isShared ? ", and from everyone you share with" : ""). Paper originals aren’t affected. It can’t be undone.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            if let me = household.me {
                HearthMemberAvatar(member: me, size: 84, ring: false)
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 3))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityHidden(true)
            }
            Text(household.me?.trimmedName ?? "Set up your household")
                .font(.title2.bold())
            // "HEARTH+" or "TROVE PLUS" when they have a plan.
            HearthMemberBadge()
            Text(TroveSharing.isShared ? "Shared with your household’s adults" : "iCloud sync on")
                .font(.footnote)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
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

/// Profile › Account: the shared Hearth account section. Trove has no Hearth server account:
/// signing in with Apple only puts your name on this device. Everything works without it.
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
                case .failure(let error as ASAuthorizationError) where error.code == .canceled:
                    break
                case .failure(let error):
                    errorMessage = error.localizedDescription
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
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your documents stay on this \(DeviceName.current) and in iCloud. Your other Hearth apps stay signed in.")
        }
        .alert("Couldn’t sign in", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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

/// A Profile row: colored icon square, title, value and chevron.
private struct ProfileRow: View {
    var symbol: String
    var color: Color
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            ProfileIcon(symbol: symbol, color: color)
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            Chevron()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(.rect)
    }
}

private struct ProfileIcon: View {
    var symbol: String
    var color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color, in: .rect(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}
