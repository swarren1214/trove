import SwiftUI

/// Screenshot mode, for marketing screenshots (scripts/screenshots.sh).
///
/// Launched with `-Screenshots`, Trove shows a demo vault in memory for the demo household
/// (Daniel and Maya, as in the other Hearth apps' screenshots): their documents, a car, the house
/// and where the originals are kept. It skips onboarding, the splash, the tour, Face ID and the
/// privacy blur, and never reads or writes iCloud or the vault's files, so the Simulator's own
/// vault is untouched. Adding `-Screen <name>` opens one screen (see `Screen`). Debug builds only:
/// Release ignores the arguments, so none of this can be reached in the App Store build.
nonisolated enum ScreenshotMode {
    static let isOn: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-Screenshots")
        #else
        return false
        #endif
    }()

    /// The screens the script captures, by the name passed after `-Screen`, in order.
    nonisolated enum Screen: String, CaseIterable {
        case home, attention, document, people, person, assets, asset, originals, place, search, add
    }

    static let screen: Screen? = {
        guard isOn else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-Screen"), arguments.indices.contains(index + 1) else { return nil }
        return Screen(rawValue: arguments[index + 1])
    }()

    /// Where the real values of the settings below wait while screenshot mode borrows them.
    private static let savedSettingsKey = "screenshots.savedSettings"
    /// The settings that would show onboarding, Face ID or the privacy blur.
    private static let borrowedKeys = [SettingsKey.onboarded, SettingsKey.faceIDLock, SettingsKey.privacyCover]

    /// At launch, before anything reads them. The real values come back on the next normal
    /// launch, so the Simulator's own Trove is as it was.
    static func prepareLaunch() {
        #if DEBUG
        let defaults = UserDefaults.standard
        guard isOn else {
            if let saved = defaults.dictionary(forKey: savedSettingsKey) {
                for key in borrowedKeys { defaults.set(saved[key], forKey: key) }
                defaults.removeObject(forKey: savedSettingsKey)
            }
            return
        }
        // Saved once: a second screenshot launch mustn't save the demo values over them.
        if defaults.dictionary(forKey: savedSettingsKey) == nil {
            var saved: [String: Any] = [:]
            for key in borrowedKeys {
                if let value = defaults.object(forKey: key) { saved[key] = value }
            }
            defaults.set(saved, forKey: savedSettingsKey)
        }
        defaults.set(true, forKey: SettingsKey.onboarded)
        defaults.set(false, forKey: SettingsKey.faceIDLock)
        defaults.set(false, forKey: SettingsKey.privacyCover)
        #endif
    }
}

extension View {
    /// Screenshot mode: opens the requested screen once the tabs are up. Does nothing otherwise.
    func screenshotScreen() -> some View {
        modifier(ScreenshotScreen())
    }
}

private struct ScreenshotScreen: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        if ScreenshotMode.isOn {
            content.task { await open() }
        } else {
            content
        }
    }

    private func open() async {
        #if DEBUG
        // Let the first screen settle before moving on from it.
        try? await Task.sleep(for: .milliseconds(400))
        switch ScreenshotMode.screen ?? .home {
        case .home: router.tab = .home
        case .attention: router.tab = .home; router.homePath = [.attention]
        case .document: router.tab = .home; router.homePath = [.document(ScreenshotSeed.featuredDocument)]
        case .people: router.tab = .people
        case .person: router.tab = .people; router.peoplePath = [.person(ScreenshotSeed.ava)]
        case .assets: router.tab = .assets
        case .asset: router.tab = .assets; router.assetsPath = [.asset(ScreenshotSeed.car)]
        case .originals: router.tab = .originals
        case .place: router.tab = .originals; router.originalsPath = [.place(ScreenshotSeed.depositBox)]
        case .search: router.tab = .search
        case .add: router.tab = .home; router.add()
        }
        #endif
    }
}

#if DEBUG
// MARK: - Demo vault

/// The Carters' vault: four people's IDs, a car, the house, and three places the originals are
/// kept. A few things need attention: two passports expiring soon, a registration due, and one
/// original nobody has placed yet.
@MainActor
enum ScreenshotSeed {
    static let daniel = "screenshots-daniel"
    static let maya = "screenshots-maya"
    static let ava = "screenshots-ava"
    static let leo = "screenshots-leo"
    static let car = "screenshots-car"
    static let house = "screenshots-house"
    static let safe = "screenshots-safe"
    static let depositBox = "screenshots-deposit-box"
    static let cabinet = "screenshots-cabinet"
    /// Opened by the document screenshot: Daniel's passport.
    static let featuredDocument = "screenshots-passport-daniel"

    /// Before anything starts: the household and the vault.
    static func stage() {
        guard ScreenshotMode.isOn else { return }
        HearthHouseholdStore.shared.showForScreenshots(household, me: daniel)
        TroveStore.shared.showForScreenshots(vault)
    }

    static let household = HearthHouseholdSnapshot(
        info: HearthHouseholdInfo(name: "The Carters", organizerID: daniel),
        members: [
            HearthMember(id: daniel, name: "Daniel Carter", role: .parent, colorHex: 0x3B82F6, birthday: "1986-02-19", sortOrder: 0),
            HearthMember(id: maya, name: "Maya Carter", role: .parent, colorHex: 0xE0457B, birthday: "1988-07-08", sortOrder: 1),
            HearthMember(id: ava, name: "Ava", role: .kid, colorHex: 0x8B5CF6, birthday: "2014-04-12", sortOrder: 2),
            HearthMember(id: leo, name: "Leo", role: .kid, colorHex: 0x10B981, birthday: "2018-09-03", sortOrder: 3),
        ]
    )

    /// "YYYY-MM-DD", `months` from today (negative for the past).
    private static func day(months: Int, days: Int = 0) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: DateComponents(month: months, day: days), to: .now) ?? .now
        return HearthDay.string(from: date)
    }

    private static func ago(months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: -months, to: .now) ?? .now
    }

    static var vault: TroveState {
        var state = TroveState()
        func add(_ document: TroveDocument) { state.documents[document.id] = document }

        state.places[safe] = TrovePlace(id: safe, name: "Home safe", kind: .safe, detail: "Primary closet, top shelf", confirmedAt: ago(months: 2))
        state.places[depositBox] = TrovePlace(id: depositBox, name: "Safe deposit box", kind: .depositBox,
                                              detail: "America First Credit Union, Orem · Box 214", contact: "(801) 555-0142",
                                              confirmedAt: ago(months: 7))
        state.places[cabinet] = TrovePlace(id: cabinet, name: "Filing cabinet", kind: .cabinet, detail: "Office, top drawer")

        state.assets[car] = TroveAsset(id: car, kind: .vehicle, name: "2021 Toyota Highlander", facts: [
            AssetFact(key: .year, value: "2021"), AssetFact(key: .make, value: "Toyota"), AssetFact(key: .model, value: "Highlander XLE"),
            AssetFact(key: .vin, value: "5TDGZRBH4MS512873"), AssetFact(key: .plate, value: "UT 7KD 2M9"),
            AssetFact(key: .insurer, value: "State Farm"),
        ])
        state.assets[house] = TroveAsset(id: house, kind: .home, name: "Maple Street house", facts: [
            AssetFact(key: .address, value: "1482 N Maple St, Lehi, UT"), AssetFact(key: .insurer, value: "State Farm"),
            AssetFact(key: .lender, value: "America First Credit Union"),
        ])

        // Passports: Daniel's and Ava's expire soon.
        add(TroveDocument(id: featuredDocument, type: .passport, title: "Daniel’s passport", owner: .person(daniel),
                          nameOnDocument: "DANIEL JAMES CARTER", number: "567812349", issuer: "U.S. Department of State",
                          issuedOn: day(months: -117), expiresOn: day(months: 3), placeID: safe, placeDetail: "Blue folder",
                          originalConfirmedAt: ago(months: 2)))
        add(TroveDocument(type: .passport, title: "Maya’s passport", owner: .person(maya), nameOnDocument: "MAYA ROSE CARTER",
                          number: "598201774", issuer: "U.S. Department of State", issuedOn: day(months: -41), expiresOn: day(months: 79),
                          placeID: safe, placeDetail: "Blue folder"))
        add(TroveDocument(type: .passport, title: "Ava’s passport", owner: .person(ava), nameOnDocument: "AVA GRACE CARTER",
                          number: "612094418", issuer: "U.S. Department of State", issuedOn: day(months: -58), expiresOn: day(months: 2),
                          placeID: safe, placeDetail: "Blue folder"))
        add(TroveDocument(type: .passport, title: "Leo’s passport", owner: .person(leo), nameOnDocument: "LEO JAMES CARTER",
                          number: "640331207", issuer: "U.S. Department of State", issuedOn: day(months: -14), expiresOn: day(months: 46),
                          placeID: safe, placeDetail: "Blue folder"))

        // Licenses travel in wallets.
        add(TroveDocument(type: .driversLicense, title: "Daniel’s driver’s license", owner: .person(daniel), nameOnDocument: "DANIEL J CARTER",
                          number: "184 220 917", issuer: "Utah Driver License Division", issuedOn: day(months: -30), expiresOn: day(months: 66),
                          noOriginal: true))
        add(TroveDocument(type: .driversLicense, title: "Maya’s driver’s license", owner: .person(maya), nameOnDocument: "MAYA R CARTER",
                          number: "190 551 302", issuer: "Utah Driver License Division", issuedOn: day(months: -50), expiresOn: day(months: 10),
                          noOriginal: true))

        // Vital records live in the deposit box.
        for (person, name) in [(daniel, "Daniel"), (maya, "Maya"), (ava, "Ava"), (leo, "Leo")] {
            add(TroveDocument(type: .birthCertificate, title: "\(name)’s birth certificate", owner: .person(person),
                              issuer: "Utah Office of Vital Records", placeID: depositBox))
        }
        // Made-up numbers (000 is never issued).
        for (person, name, number) in [(daniel, "Daniel", "000-41-7302"), (maya, "Maya", "000-58-2216"),
                                       (ava, "Ava", "000-63-9045"), (leo, "Leo", "000-72-1188")] {
            add(TroveDocument(type: .socialSecurityCard, title: "\(name)’s Social Security card", owner: .person(person),
                              number: number, issuer: "Social Security Administration", placeID: depositBox))
        }
        add(TroveDocument(type: .marriageCertificate, owner: .household, issuer: "Utah County Clerk", issuedOn: "2011-06-18", placeID: depositBox))
        add(TroveDocument(type: .will, title: "Wills and trust", owner: .household, issuer: "Hansen & Ruiz Law", issuedOn: day(months: -26),
                          placeID: depositBox, notes: "Copies with the attorney's office."))

        // The car: the registration is due, and nobody has said where the title is.
        add(TroveDocument(type: .vehicleTitle, owner: .asset(car), issuer: "Utah DMV", issuedOn: day(months: -40)))
        add(TroveDocument(type: .vehicleRegistration, owner: .asset(car), issuer: "Utah DMV", expiresOn: day(months: 0, days: 24), noOriginal: true))
        add(TroveDocument(type: .insuranceCard, owner: .asset(car), number: "48-C1-7729-3", issuer: "State Farm", expiresOn: day(months: 4),
                          noOriginal: true))

        // The house.
        add(TroveDocument(type: .deed, owner: .asset(house), issuer: "Utah County Recorder", issuedOn: "2019-08-30", placeID: depositBox))
        add(TroveDocument(type: .mortgage, owner: .asset(house), issuer: "America First Credit Union", issuedOn: "2019-08-30", placeID: cabinet))
        add(TroveDocument(type: .insurancePolicy, title: "Homeowners policy", owner: .asset(house), number: "93-BX-1150-6", issuer: "State Farm",
                          expiresOn: day(months: 7), placeID: cabinet))
        add(TroveDocument(type: .warranty, title: "Refrigerator warranty", owner: .household, issuer: "Samsung", issuedOn: day(months: -9),
                          expiresOn: day(months: 15), placeID: cabinet))
        return state
    }
}
#endif
