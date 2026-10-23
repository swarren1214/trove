import Foundation

/// Shares the vault with the household's parents and adults through `HearthAppSharing`, so the
/// family accepts one invitation (the household's) for every Hearth app. Kids are never in the
/// vault: their documents belong to their parents.
@MainActor
enum TroveSharing {
    private static var isRunning = false

    /// Call on launch, coming to the foreground and when the household changes. Safe to call
    /// often: it only changes what's out of date.
    static func update() async {
        guard !ScreenshotMode.isOn else { return }
        let household = HearthHouseholdStore.shared
        guard !isRunning, household.exists else { return }
        isRunning = true
        defer { isRunning = false }
        var joinedOwner: String?
        await HearthAppSharing.update(app: .trove, zoneName: TroveStore.vaultZoneName, title: "Important Documents", audience: .adults) { owner in
            joinedOwner = owner
        }
        if let joinedOwner, !TroveStore.shared.isInFamilyVault {
            TroveStore.shared.markJoined(joinedOwner)
            await TroveStore.shared.syncNow()
        }
    }

    /// Whether anyone else can see the vault: the household's other adults are in it, or this is
    /// the family's vault.
    static var isShared: Bool {
        let household = HearthHouseholdStore.shared
        if TroveStore.shared.isInFamilyVault { return true }
        return household.info?.appShareURLs[HearthApp.trove.rawValue] != nil
            && household.participants.contains { $0.acceptanceStatus == .accepted && $0.permission == .readWrite }
    }
}
