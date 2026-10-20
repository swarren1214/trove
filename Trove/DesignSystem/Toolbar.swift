import SwiftUI

/// The person's photo (or initial) at the top right of every screen. Opens Profile.
///
/// Drawn as a live view, not an image: the toolbar repaints images in one flat color, which
/// would turn a photo into a plain white circle.
struct ProfileButton: View {
    @State private var household = HearthHouseholdStore.shared

    var body: some View {
        NavigationLink(value: Destination.profile) {
            if let me = household.me {
                HearthMemberAvatar(member: me, size: 30, ring: false)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("Profile")
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
                // is jade, which would make menu icons jade beside white text).
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
