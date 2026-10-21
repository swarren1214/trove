import SwiftUI

/// People: everyone in the Hearth household, and each person's papers: the essentials every
/// person should have (scanned, and the original found), then everything else that's theirs.
/// From the Trove canvas.
struct PeopleView: View {
    @Environment(AppRouter.self) private var router
    @State private var household = HearthHouseholdStore.shared
    @State private var store = TroveStore.shared
    @SceneStorage("people.selected") private var selectedID = ""

    private var selected: HearthMember? {
        household.member(selectedID).flatMap { $0.isArchived ? nil : $0 } ?? household.me ?? household.people.first
    }

    var body: some View {
        TroveScreen("People") {
            if household.people.isEmpty {
                EmptyCard(systemName: HearthHouseholdLabel.symbol, title: "Your household", message: "Add your family in Household to keep each person’s papers together.")
                Button {
                    HearthProfilePresenter.shared.show()
                } label: {
                    Text("Open Profile").font(.headline).frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.sky)
            } else {
                switcher
                if let selected {
                    PersonDocuments(person: selected)
                }
            }
        }
        .refreshable {
            await household.refresh()
            await store.syncNow()
        }
        .troveToolbar {
            Button("Add Document", systemImage: "plus") {
                router.add(AddDocumentRequest(owner: selected.map { .person($0.id) }))
            }
        }
    }

    /// The household's people as avatars; the one showing is ringed.
    private var switcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(household.people) { person in
                    let isSelected = person.id == selected?.id
                    Button {
                        withAnimation(.snappy) { selectedID = person.id }
                    } label: {
                        VStack(spacing: 6) {
                            HearthMemberAvatar(member: person, size: 54, ring: false)
                                .padding(3)
                                .overlay(Circle().strokeBorder(.white, lineWidth: isSelected ? 3 : 0))
                                .opacity(isSelected ? 1 : 0.85)
                            Text(person.firstName)
                                .font(.footnote.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.85))
                                .lineLimit(1)
                        }
                        .frame(width: 64)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(person.trimmedName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

/// One person's papers, pushed from search or a document.
struct PersonDocumentsView: View {
    let personID: String
    @State private var household = HearthHouseholdStore.shared
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let person = household.member(personID) {
            TroveScreen(person.trimmedName, eyebrow: person.role.label) {
                PersonDocuments(person: person)
            }
            .refreshable {
                await household.refresh()
                await TroveStore.shared.syncNow()
            }
            .troveToolbar {
                Button("Add Document", systemImage: "plus") {
                    router.add(AddDocumentRequest(owner: .person(person.id)))
                }
            }
        } else {
            ContentUnavailableView("Not in the household any more", systemImage: "person.slash")
                .troveToolbar()
        }
    }
}

/// The essentials card and the person's documents by group.
struct PersonDocuments: View {
    var person: HearthMember
    @Environment(AppRouter.self) private var router
    @State private var store = TroveStore.shared

    /// What every person should have, by age.
    private var essentials: [DocumentType] {
        let age = person.age()
        if person.isKid || (age ?? 99) < 16 { return [.birthCertificate, .socialSecurityCard, .passport] }
        return [.passport, .driversLicense, .socialSecurityCard, .birthCertificate]
    }

    var body: some View {
        let documents = store.documents(for: .person(person.id))
        let present = essentials.filter { type in documents.contains { $0.type == type } }
        let located = essentials.filter { type in documents.contains { $0.type == type && $0.placeID != nil } }

        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(person.firstName)’s essentials").font(.headline)
                    Text("\(present.count) of \(essentials.count) in Trove · \(located.count) \(located.count == 1 ? "original" : "originals") located")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CompletenessRing(done: present.count, total: essentials.count)
            }
        }

        CardLabel("Essentials")
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(essentials.enumerated()), id: \.element) { index, type in
                    if let document = documents.first(where: { $0.type == type }) {
                        NavigationLink(value: Destination.document(document.id)) {
                            EssentialRow(type: type, document: document)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            router.add(AddDocumentRequest(owner: .person(person.id), type: type))
                        } label: {
                            EssentialRow(type: type, document: nil)
                        }
                        .buttonStyle(.plain)
                    }
                    if index < essentials.count - 1 { Divider().padding(.leading, 16) }
                }
            }
        }

        let others = documents.filter { !essentials.contains($0.type) }
        if !others.isEmpty {
            CardLabel("More of \(person.firstName)’s")
            CardList(items: others, inset: 62) { document in
                NavigationLink(value: Destination.document(document.id)) {
                    DocumentRow(document: document)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// An essential: done (scanned and its original located), needs a location, or not added yet.
private struct EssentialRow: View {
    var type: DocumentType
    var document: TroveDocument?
    @State private var store = TroveStore.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(type.label).foregroundStyle(document == nil ? .secondary : .primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(document == nil ? Brand.ink : (needsPlace ? Urgency.soon.ink : Color(.secondaryLabel)))
            }
            Spacer()
            status
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var needsPlace: Bool { document?.originalIsMissing ?? false }

    private var detail: String {
        guard let document else { return "Scan to add" }
        var parts: [String] = []
        if let line = Attention.expiryLine(document) { parts.append(line.text) }
        if let place = store.place(document.placeID) {
            parts.append(place.name)
        } else if needsPlace {
            parts.append(document.scans.isEmpty ? "Where’s the original?" : "Scanned · where’s the original?")
        }
        return parts.isEmpty ? "Added" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var status: some View {
        if document == nil {
            Image(systemName: "circle.dashed")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Not added")
        } else if needsPlace {
            Image(systemName: "exclamationmark.circle")
                .font(.title3)
                .foregroundStyle(Urgency.soon.ink)
                .accessibilityLabel("Needs a location")
        } else {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(Brand.ink)
                .accessibilityLabel("Complete")
        }
    }
}

/// "4/5" in a ring that fills as essentials are added.
struct CompletenessRing: View {
    var done: Int
    var total: Int

    var body: some View {
        let progress = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().stroke(Color(.systemGray5), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Brand.sky, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .frame(width: 46, height: 46)
        .animation(.smooth, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) essentials")
    }
}

/// Trove's section on a person's page in Household (`\.hearthPersonExtras`): their documents,
/// and how many essentials are in Trove.
struct TrovePersonExtras: View {
    var person: HearthMember
    @State private var store = TroveStore.shared

    var body: some View {
        let documents = store.documents(for: .person(person.id))
        Section {
            if documents.isEmpty {
                Text("No documents in Trove yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(documents) { document in
                    NavigationLink(value: Destination.document(document.id)) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(document.displayTitle)
                                if let line = Attention.expiryLine(document) {
                                    Text(line.text)
                                        .font(.footnote)
                                        .foregroundStyle(line.urgency == .calm ? Color(.secondaryLabel) : line.urgency.ink)
                                }
                            }
                        } icon: {
                            Image(systemName: document.type.symbol).foregroundStyle(Brand.ink)
                        }
                    }
                }
            }
        } header: {
            Text("Documents in Trove")
        }
    }
}
