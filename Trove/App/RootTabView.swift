import SwiftUI

/// The system Liquid Glass tab bar from the Trove canvas: Home, Assets, People and Originals in
/// the capsule, and Search as the separate round button (the search tab, which iOS draws in its
/// own circle). The Add Document sheet opens over any tab.
struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab(value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView().troveDestinations()
                }
            } label: {
                tabLabel("Home", "archivebox")
            }

            Tab(value: AppTab.assets) {
                NavigationStack(path: $router.assetsPath) {
                    AssetsView().troveDestinations()
                }
            } label: {
                tabLabel("Assets", "square.grid.2x2")
            }

            Tab(value: AppTab.people) {
                NavigationStack(path: $router.peoplePath) {
                    PeopleView().troveDestinations()
                }
            } label: {
                tabLabel("People", "person.2")
            }

            Tab(value: AppTab.originals) {
                NavigationStack(path: $router.originalsPath) {
                    OriginalsView().troveDestinations()
                }
            } label: {
                tabLabel("Originals", "mappin.and.ellipse")
            }

            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $router.searchPath) {
                    SearchView().troveDestinations()
                }
            } label: {
                if sizeClass == .regular {
                    Label { Text("Search") } icon: { Image.menuIcon("magnifyingglass") }
                } else {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
        }
        // iPad: a tab bar at the top that opens into a sidebar.
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSearchActivation(.searchTabSelection)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Profile, opened by the photo at the top right of every main screen.
        .hearthProfile { ProfileView() }
        // The tour (HearthTour.swift): Welcome after onboarding, then one step per tab.
        .hearthTour(app: .trove, steps: TroveTour.steps, finishTitle: "Got It", autoStart: !ScreenshotMode.isOn) { step in
            router.tab = TroveTour.tab(for: step)
        }
        .sheet(item: $router.adding) { request in
            AddDocumentSheet(request: request)
        }
        .screenshotScreen()
    }

    /// Icon only in the iPhone tab bar, as in every Hearth app (VoiceOver still reads the
    /// name); icon and name on iPad, where the tabs also show in the sidebar and the icon is the
    /// color of its name instead of the app's tint (see AGENT.md).
    @ViewBuilder
    private func tabLabel(_ title: String, _ systemImage: String) -> some View {
        if sizeClass == .regular {
            Label { Text(title) } icon: { Image.menuIcon(systemImage) }
        } else {
            Image(systemName: systemImage)
                .accessibilityLabel(title)
        }
    }
}
