import SwiftUI

/// Search across documents, assets, people and places: "passport", "Highlander", "warranty",
/// "fire safe". Document numbers are never searched, so they never show in results by accident.
struct SearchView: View {
    @State private var store = TroveStore.shared
    @State private var household = HearthHouseholdStore.shared
    @State private var query = ""

    var body: some View {
        List {
            if trimmed.isEmpty {
                Section("Browse") {
                    ForEach(DocumentType.Group.allCases) { group in
                        let count = store.documents.filter { $0.type.group == group }.count
                        if count > 0 {
                            NavigationLink {
                                GroupDocumentsView(group: group)
                            } label: {
                                LabeledContent(group.title, value: "\(count)")
                            }
                        }
                    }
                }
            } else {
                let documents = matchingDocuments
                let assets = store.assets.filter { matches($0.name) || matches($0.kind.label) || $0.facts.contains { !$0.key.isSensitive && matches($0.value) } }
                let people = household.people.filter { matches($0.trimmedName) }
                let places = store.places.filter { matches($0.name) || matches($0.detail) }
                if documents.isEmpty && assets.isEmpty && people.isEmpty && places.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                }
                if !documents.isEmpty {
                    Section("Documents") {
                        ForEach(documents) { document in
                            NavigationLink(value: Destination.document(document.id)) {
                                SearchRow(symbol: document.type.symbol, title: Attention.title(of: document), detail: Attention.expiryLine(document)?.text ?? document.type.label)
                            }
                        }
                    }
                }
                if !assets.isEmpty {
                    Section("Assets") {
                        ForEach(assets) { asset in
                            NavigationLink(value: Destination.asset(asset.id)) {
                                SearchRow(symbol: asset.kind.symbol, title: asset.name, detail: asset.kind.label)
                            }
                        }
                    }
                }
                if !people.isEmpty {
                    Section("People") {
                        ForEach(people) { person in
                            NavigationLink(value: Destination.person(person.id)) {
                                HStack(spacing: 12) {
                                    HearthMemberAvatar(member: person, size: 30, ring: false)
                                    Text(person.trimmedName)
                                }
                            }
                        }
                    }
                }
                if !places.isEmpty {
                    Section("Places") {
                        ForEach(places) { place in
                            NavigationLink(value: Destination.place(place.id)) {
                                SearchRow(symbol: place.kind.symbol, title: place.name, detail: place.detail.isEmpty ? place.kind.label : place.detail)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Passport, Highlander, warranty, fire safe")
        .refreshable { await store.syncNow() }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matches(_ text: String) -> Bool {
        !text.isEmpty && text.localizedStandardContains(trimmed)
    }

    private var matchingDocuments: [TroveDocument] {
        store.documents.filter { document in
            matches(document.displayTitle) || matches(document.type.label) || matches(Attention.title(of: document))
                || matches(store.ownerName(document.owner)) || matches(document.issuer) || matches(document.notes)
                || matches(store.place(document.placeID)?.name ?? "")
        }
    }
}

private struct SearchRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Search › Browse: every document of one kind. Where there's room (regular width in
/// landscape, iPhone Duo open wide, or partly folded), the list sits beside the document it has
/// selected, in equal panes clear of the fold (`HearthFoldSplit`). Otherwise rows push the
/// document, as before.
private struct GroupDocumentsView: View {
    var group: DocumentType.Group
    @State private var store = TroveStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.hearthDuoPose) private var pose
    /// The document beside the list. Kept here, above both layouts, so it survives rotating,
    /// folding and unfolding.
    @State private var selectedID: String?

    private var documents: [TroveDocument] {
        store.documents.filter { $0.type.group == group }
    }

    var body: some View {
        GeometryReader { proxy in
            let roomy = sizeClass == .regular && (proxy.size.width > proxy.size.height || pose.isFolded)
            // A removed document falls back to the first one.
            if roomy, let selected = documents.first(where: { $0.id == selectedID }) ?? documents.first {
                HearthFoldSplit {
                    list(selection: selected.id)
                } secondary: {
                    DocumentDetailView(documentID: selected.id, inPane: true)
                        .id(selected.id)
                }
            } else {
                list(selection: nil)
            }
        }
        .navigationTitle(group.title)
        .refreshable { await store.syncNow() }
    }

    /// The documents: rows select the one beside the list when there's a `selection`, and push
    /// it when there isn't.
    private func list(selection: String?) -> some View {
        List {
            ForEach(documents) { document in
                let row = SearchRow(symbol: document.type.symbol, title: Attention.title(of: document), detail: Attention.expiryLine(document)?.text ?? document.type.label)
                if let selection {
                    let isSelected = document.id == selection
                    Button {
                        selectedID = document.id
                    } label: {
                        row
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .tint(.primary)
                    .listRowBackground(isSelected ? Color(.tertiarySystemFill) : nil)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                } else {
                    NavigationLink(value: Destination.document(document.id)) { row }
                }
            }
        }
    }
}
