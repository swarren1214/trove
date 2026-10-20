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

/// Search › Browse: every document of one kind.
private struct GroupDocumentsView: View {
    var group: DocumentType.Group
    @State private var store = TroveStore.shared

    var body: some View {
        List {
            ForEach(store.documents.filter { $0.type.group == group }) { document in
                NavigationLink(value: Destination.document(document.id)) {
                    SearchRow(symbol: document.type.symbol, title: Attention.title(of: document), detail: Attention.expiryLine(document)?.text ?? document.type.label)
                }
            }
        }
        .navigationTitle(group.title)
        .refreshable { await store.syncNow() }
    }
}
