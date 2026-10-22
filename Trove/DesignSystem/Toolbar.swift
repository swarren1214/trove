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
    /// `overColorHeader` false: the bar isn't over the blue header (a pane beside a plain list),
    /// so the icons take the text color instead of white.
    func troveToolbar<Actions: View>(showsProfile: Bool = true, overColorHeader: Bool = true, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        toolbar {
            // `.primaryAction` (the trailing end of the bar on iPhone and iPad) rather than a fixed
            // edge, so on iPhone Duo's outer display the system can move the group to its rail.
            ToolbarItemGroup(placement: .primaryAction) {
                // White icons, also in the "…" menu if the bar runs out of room (the app's tint
                // is blue, which would make menu icons blue beside white text).
                actions().tint(overColorHeader ? Color.white : Color.primary)
                if showsProfile {
                    ProfileButton()
                }
            }
        }
    }

    func troveToolbar(showsProfile: Bool = true, overColorHeader: Bool = true) -> some View {
        troveToolbar(showsProfile: showsProfile, overColorHeader: overColorHeader) { EmptyView() }
    }
}
