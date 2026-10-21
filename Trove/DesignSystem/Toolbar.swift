import SwiftUI

/// The person's photo at the top right of every screen: the shared Hearth profile button
/// (HearthProfile.swift), the same in every Hearth app. Opens the Profile sheet.
struct ProfileButton: View {
    var body: some View {
        HearthProfileButton()
    }
}

extension View {
    /// The top bar for every main screen: the screen's actions and the profile avatar share one
    /// Liquid Glass capsule at the top right, the avatar always last, so it's always in the same
    /// place. Icons are white over the color header.
    func troveToolbar<Actions: View>(showsProfile: Bool = true, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // White icons, also in the "…" menu if the bar runs out of room (the app's tint
                // is blue, which would make menu icons blue beside white text).
                actions().tint(.white)
                if showsProfile {
                    ProfileButton()
                }
            }
        }
    }

    func troveToolbar(showsProfile: Bool = true) -> some View {
        troveToolbar(showsProfile: showsProfile) { EmptyView() }
    }
}
