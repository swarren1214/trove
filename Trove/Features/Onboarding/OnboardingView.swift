import AuthenticationServices
import SwiftUI

/// The first launch, from the Hearth Onboarding canvas (Trove row): Welcome (Sign in with Apple
/// is optional), the household, what Trove should keep, where the originals are, reminders, the
/// Face ID lock, All Set, then Better with Hearth. Built from HearthKit's onboarding pieces
/// (HearthOnboarding.swift), always dark. Every step after the household can be skipped.
///
/// What it sets up is real: the picked kinds of documents are Home's "Start with" list, the
/// picked places become places in Originals, and the reminder and lock choices are Profile's.
struct OnboardingView: View {
    @Environment(AppLock.self) private var lock
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.faceIDLock) private var faceIDLock = true
    @AppStorage(SettingsKey.lockAfterSeconds) private var lockAfter = 60
    @AppStorage(SettingsKey.expiryReminders) private var expiryReminders = true
    @AppStorage(SettingsKey.placeReminders) private var placeReminders = true
    @AppStorage(SettingsKey.firstDocuments) private var firstDocuments = ""
    @AppStorage(SettingsKey.appleUserID) private var appleUserID = ""
    @AppStorage(SettingsKey.appleName) private var appleName = ""
    @AppStorage(SettingsKey.appleEmail) private var appleEmail = ""

    private enum Step: Int, CaseIterable {
        case welcome, household, keep, originals, reminders, lock, ready, apps
    }

    @State private var step: Step = .welcome
    @State private var isForward = true
    @State private var keep: Set<String> = OnboardingView.defaultKeep
    @State private var places: Set<String> = ["Fire safe", "Filing cabinet"]
    @State private var lockAfterChoice: Set<String> = ["1 minute"]
    @State private var errorMessage: String?
    @State private var household = HearthHouseholdStore.shared
    @State private var store = TroveStore.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            screen
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
                ))
        }
        .hearthOnboardingStyle(.trove)
        .alert("Couldn’t Sign In", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch step {
        case .welcome: welcome
        case .household:
            HearthHouseholdOnboarding(accent: HearthOnboarding.ink(.trove)) { go(.keep) }
                .background(Color.black.ignoresSafeArea())
        case .keep: keepStep
        case .originals: originalsStep
        case .reminders: remindersStep
        case .lock: lockStep
        case .ready: ready
        case .apps:
            HearthOnboardingAppsPage(app: .trove, finish: finish, jumpInTitle: "Scan a Document")
        }
    }

    private func go(_ next: Step) {
        isForward = next.rawValue > step.rawValue
        withAnimation(.smooth) { step = next }
    }

    // MARK: Welcome

    private var welcome: some View {
        HearthOnboardingPage(
            app: .trove,
            title: "Trove",
            subtitle: "Your family’s important papers, and where the originals are."
        ) {
            VStack(spacing: 20) {
                HearthOnboardingFeature(app: .trove, symbol: "doc.viewfinder", title: "Scan once", detail: "Trove reads the type, owner and dates on this \(DeviceName.current), and keeps the original photo.")
                HearthOnboardingFeature(app: .trove, symbol: "mappin.and.ellipse", title: "Where the original is", detail: "The fire safe, the safe deposit box, the attorney’s office. Never hunt for a birth certificate again.")
                HearthOnboardingFeature(app: .trove, symbol: "calendar.badge.exclamationmark", title: "Before it expires", detail: "Passports nine months ahead, registrations six weeks ahead, with what renewing takes.")
            }
        } controls: {
            if appleUserID.isEmpty {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    signedIn(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(Capsule())
                HearthOnboardingButtons(
                    app: .trove,
                    secondary: "Continue Without an Account", secondaryAction: { go(.household) },
                    footnote: "Optional. Your documents stay in your iCloud and on this \(DeviceName.current), never on Hearth’s servers."
                )
            } else {
                HearthOnboardingButtons(
                    app: .trove,
                    primary: appleName.isEmpty ? "Continue" : "Continue as \(appleName.split(separator: " ").first.map(String.init) ?? appleName)",
                    action: { go(.household) },
                    footnote: "Signed in with Apple on this \(DeviceName.current)."
                )
            }
        }
    }

    /// The same as Profile › Account: the name and email Apple shares (only the first time, so
    /// another Hearth app's copy fills in).
    private func signedIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            appleUserID = credential.user
            if let name = credential.fullName?.formatted(), !name.isEmpty { appleName = name }
            if let email = credential.email { appleEmail = email }
            if appleName.isEmpty, let shared = HearthAccounts.appleID(), shared.userID == credential.user {
                appleName = shared.fullName ?? ""
                appleEmail = appleEmail.isEmpty ? (shared.email ?? "") : appleEmail
            }
            go(.household)
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            break
        case .failure(let error):
            errorMessage = FriendlyError.signIn(error)
        }
    }

    // MARK: What to keep

    /// The chips, and the document each stands for on Home's "Start with" list.
    private static let keepChoices: [(label: String, type: DocumentType)] = [
        ("Passports", .passport),
        ("Driver’s licenses", .driversLicense),
        ("Birth certificates", .birthCertificate),
        ("Social Security cards", .socialSecurityCard),
        ("Insurance cards", .insuranceCard),
        ("Car titles", .vehicleTitle),
        ("Home and mortgage", .mortgage),
        ("Warranties", .warranty),
        ("Wills and estate", .will),
        ("Marriage certificates", .marriageCertificate),
    ]
    private static let defaultKeep: Set<String> = ["Passports", "Driver’s licenses", "Birth certificates", "Insurance cards"]

    private var keepStep: some View {
        HearthOnboardingPage(
            app: .trove,
            step: (2, 5),
            symbol: "folder",
            title: "What should Trove keep?",
            subtitle: "Tap what your family has. Home lists them as the first to scan."
        ) {
            HearthOnboardingChips(options: Self.keepChoices.map { $0.label }, selection: $keep)
        } controls: {
            HearthOnboardingButtons(
                app: .trove,
                primary: "Continue", action: {
                    let picked = Self.keepChoices.filter { keep.contains($0.label) }.map { $0.type.rawValue }
                    firstDocuments = picked.joined(separator: ",")
                    go(.originals)
                },
                secondary: "Skip", secondaryAction: { go(.originals) }
            )
        }
    }

    // MARK: Where the originals are

    private static let placeChoices: [(label: String, kind: PlaceKind)] = [
        ("Fire safe", .safe),
        ("Filing cabinet", .cabinet),
        ("Safe deposit box", .depositBox),
        ("Attorney’s office", .person),
        ("Desk drawer", .cabinet),
        ("With a relative", .person),
    ]

    private var originalsStep: some View {
        HearthOnboardingPage(
            app: .trove,
            step: (3, 5),
            symbol: "mappin.and.ellipse",
            title: "Where are the originals?",
            subtitle: "The places your paper copies live. Each document remembers which one."
        ) {
            HearthOnboardingChips(options: Self.placeChoices.map { $0.label }, selection: $places)
            HearthOnboardingNote("Add more places, and details like “top shelf”, anytime in Originals.")
        } controls: {
            HearthOnboardingButtons(
                app: .trove,
                primary: "Continue", action: {
                    addPlaces()
                    go(.reminders)
                },
                secondary: "Skip", secondaryAction: { go(.reminders) }
            )
        }
    }

    /// The picked places, as places in Originals (skipping any the vault already has by name,
    /// such as the family's when this person joined a household).
    private func addPlaces() {
        let existing = Set(store.places.map { $0.name.localizedLowercase })
        for choice in Self.placeChoices where places.contains(choice.label) && !existing.contains(choice.label.localizedLowercase) {
            store.save(TrovePlace(name: choice.label, kind: choice.kind))
        }
    }

    // MARK: Reminders

    private var remindersStep: some View {
        HearthOnboardingPage(
            app: .trove,
            step: (4, 5),
            symbol: "bell",
            title: "Know before it expires",
            subtitle: "Early enough to renew, with what renewing takes."
        ) {
            HearthOnboardingCard {
                Toggle(isOn: $expiryReminders) {
                    HearthOnboardingRowLabel("Expiration Reminders", detail: "Passports 9 months ahead, registrations 6 weeks")
                }
                Toggle(isOn: $placeReminders) {
                    HearthOnboardingRowLabel("Check on the Originals", detail: "Once a year, a nudge to look in each place")
                }
            }
        } controls: {
            HearthOnboardingButtons(
                app: .trove,
                primary: "Turn On Reminders", action: {
                    Task {
                        if expiryReminders || placeReminders {
                            let granted = await Reminders.requestPermission()
                            if !granted {
                                expiryReminders = false
                                placeReminders = false
                            }
                        }
                        Reminders.schedule()
                        go(.lock)
                    }
                },
                secondary: "Not Now", secondaryAction: {
                    expiryReminders = false
                    placeReminders = false
                    go(.lock)
                }
            )
        }
    }

    // MARK: Face ID

    private static let lockChoices: [(label: String, seconds: Int)] = [
        ("Right away", 0), ("1 minute", 60), ("5 minutes", 300), ("15 minutes", 900),
    ]

    private var lockStep: some View {
        HearthOnboardingPage(
            app: .trove,
            step: (5, 5),
            symbol: "faceid",
            title: "Keep it locked",
            subtitle: "Trove holds your family’s most private papers. \(lock.biometryName) keeps them that way."
        ) {
            HearthOnboardingCard {
                Toggle("Lock with \(lock.biometryName)", isOn: Binding(
                    get: { faceIDLock },
                    set: { faceIDLock = $0 && lock.canLock() }
                ))
            }
            if faceIDLock {
                Text("Lock After")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                HearthOnboardingChips(options: Self.lockChoices.map { $0.label }, selection: $lockAfterChoice, single: true)
            }
            HearthOnboardingNote("The app switcher always shows a cover, never a document.")
        } controls: {
            HearthOnboardingButtons(
                app: .trove,
                primary: "Use \(lock.biometryName)", action: {
                    faceIDLock = lock.canLock()
                    saveLockAfter()
                    go(.ready)
                },
                secondary: "Not Now", secondaryAction: {
                    faceIDLock = false
                    go(.ready)
                }
            )
        }
        .onAppear {
            if let current = Self.lockChoices.first(where: { $0.seconds == lockAfter }) {
                lockAfterChoice = [current.label]
            }
        }
    }

    private func saveLockAfter() {
        if let choice = Self.lockChoices.first(where: { lockAfterChoice.contains($0.label) }) {
            lockAfter = choice.seconds
        }
    }

    // MARK: All set

    private var ready: some View {
        HearthOnboardingPage(
            app: .trove,
            symbol: "checkmark",
            title: "You’re all set",
            subtitle: "Start with a passport: it takes a few seconds."
        ) {
            VStack(spacing: 14) {
                HearthOnboardingSummaryRow(app: .trove, title: peopleLine, detail: "Each with their own papers")
                HearthOnboardingSummaryRow(app: .trove, title: documentsLine, detail: "On Home, ready to scan")
                HearthOnboardingSummaryRow(app: .trove, title: placesLine, detail: "Each document remembers where")
                HearthOnboardingSummaryRow(app: .trove, title: protectionLine, detail: protectionDetail)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22, style: .continuous))
        } controls: {
            HearthOnboardingButtons(app: .trove, primary: "Continue", action: { go(.apps) })
        }
    }

    private var peopleLine: String {
        let count = max(household.people.filter { !$0.isArchived }.count, 1)
        return count == 1 ? "Just you, for now" : "\(count) people in your household"
    }

    private var documentsLine: String {
        let count = firstDocuments.split(separator: ",").count
        return count == 0 ? "The usual papers to gather" : (count == 1 ? "1 kind of document to gather" : "\(count) kinds of documents to gather")
    }

    private var placesLine: String {
        let names = store.places.map { $0.name }
        switch names.count {
        case 0: return "Originals: add places anytime"
        case 1: return "Originals in the \(names[0].localizedLowercase)"
        case 2: return "Originals in the \(names[0].localizedLowercase) and \(names[1].localizedLowercase)"
        default: return "Originals in \(names.count) places"
        }
    }

    private var protectionLine: String {
        let reminders = expiryReminders || placeReminders
        switch (reminders, faceIDLock) {
        case (true, true): return "Reminders and \(lock.biometryName) on"
        case (true, false): return "Reminders on"
        case (false, true): return "\(lock.biometryName) on"
        case (false, false): return "Reminders and \(lock.biometryName) are off"
        }
    }

    private var protectionDetail: String {
        expiryReminders || placeReminders || faceIDLock ? "Nothing expires by surprise" : "Turn them on anytime in Profile"
    }

    // MARK: Finish

    /// Better with Hearth: Show Me Around starts the tour; Scan a Document opens New Document.
    private func finish(_ tour: Bool) {
        HearthOnboarding.finish(.trove, tour: tour)
        withAnimation { onboarded = true }
        if !tour {
            // Once the tabs are up (the Add Document sheet hangs off them).
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                router.add(AddDocumentRequest())
            }
        }
    }
}
