import Observation
import SwiftUI

enum AppTab: Hashable {
    case home, assets, people, originals, search
}

/// A screen any tab can push.
enum Destination: Hashable {
    case document(String)
    case asset(String)
    case place(String)
    case person(String)
    case attention
    case profile
}

/// Which tab is showing, each tab's path, and what's being added.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var tab: AppTab = .home
    var homePath: [Destination] = []
    var assetsPath: [Destination] = []
    var peoplePath: [Destination] = []
    var originalsPath: [Destination] = []
    var searchPath: [Destination] = []

    /// The Add Document sheet, with what's known up front.
    var adding: AddDocumentRequest?

    /// Opens a screen from outside the app's own navigation (a notification, a link): on Home,
    /// over whatever was there.
    func open(_ destination: Destination) {
        tab = .home
        homePath = [destination]
    }

    func add(_ request: AddDocumentRequest = AddDocumentRequest()) {
        adding = request
    }
}

/// Starts the Add Document sheet already knowing some things: whose it is, what it is.
struct AddDocumentRequest: Identifiable, Hashable {
    var id = UUID()
    var owner: DocumentOwner?
    var type: DocumentType?
    /// Open straight to the camera.
    var scanFirst = false
    /// New pages for a document that's already in Trove (Rescan), instead of a new document.
    var documentID: String?
}

extension View {
    /// The screens every tab can push.
    func troveDestinations() -> some View {
        navigationDestination(for: Destination.self) { destination in
            switch destination {
            case .document(let id): DocumentDetailView(documentID: id)
            case .asset(let id): AssetDetailView(assetID: id)
            case .place(let id): PlaceDetailView(placeID: id)
            case .person(let id): PersonDocumentsView(personID: id)
            case .attention: AttentionListView()
            case .profile: ProfileView()
            }
        }
    }
}
