import SwiftUI

/// Where a document's paper original is: pick a place (or add one), add a detail like "top
/// shelf", or say there's no paper original.
struct PlacePicker: View {
    var document: TroveDocument
    @Environment(\.dismiss) private var dismiss
    @State private var store = TroveStore.shared
    @State private var placeID: String?
    @State private var detail: String
    @State private var noOriginal: Bool
    @State private var addingPlace = false

    init(document: TroveDocument) {
        self.document = document
        _placeID = State(initialValue: document.placeID)
        _detail = State(initialValue: document.placeDetail)
        _noOriginal = State(initialValue: document.noOriginal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlaceChoices(selection: $placeID, noOriginal: $noOriginal)
                    Button("New Place", systemImage: "plus") { addingPlace = true }
                } footer: {
                    Text("Only the place’s name is in Trove, never a safe’s combination.")
                }
                if placeID != nil {
                    Section("Exactly where") {
                        TextField("Top shelf, blue folder", text: $detail)
                    }
                }
            }
            .navigationTitle("Where’s the Original?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCancelButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton("Save") { save() } }
            }
            .sheet(isPresented: $addingPlace) {
                PlaceEditor(place: nil) { added in
                    placeID = added.id
                    noOriginal = false
                }
            }
        }
    }

    private func save() {
        var updated = document
        if updated.placeID != placeID { updated.originalConfirmedAt = placeID == nil ? nil : .now }
        updated.placeID = placeID
        updated.placeDetail = placeID == nil ? "" : detail.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.noOriginal = placeID == nil && noOriginal
        store.save(updated)
        dismiss()
    }
}

/// The places as a list to pick from, with "Not sure yet" and "No paper original". The
/// checkmark is on the right, as in every Hearth app's selection lists.
struct PlaceChoices: View {
    @Binding var selection: String?
    @Binding var noOriginal: Bool
    @State private var store = TroveStore.shared

    var body: some View {
        ForEach(store.places) { place in
            choice(place.name, symbol: place.kind.symbol, detail: place.detail, selected: selection == place.id) {
                selection = place.id
                noOriginal = false
            }
        }
        choice("Not sure yet", symbol: "questionmark.circle", detail: nil, selected: selection == nil && !noOriginal) {
            selection = nil
            noOriginal = false
        }
        choice("No paper original", symbol: "iphone", detail: "A digital card, or an email", selected: selection == nil && noOriginal) {
            selection = nil
            noOriginal = true
        }
    }

    private func choice(_ title: String, symbol: String, detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Brand.ink)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Adding or editing a place.
struct PlaceEditor: View {
    var place: TrovePlace?
    var onSave: ((TrovePlace) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrovePlace
    @State private var store = TroveStore.shared

    init(place: TrovePlace?, onSave: ((TrovePlace) -> Void)? = nil) {
        self.place = place
        self.onSave = onSave
        _draft = State(initialValue: place ?? TrovePlace(name: "", kind: .safe))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Fire safe", text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(PlaceKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    // A list with the checkmark on the right, not a menu (see AGENT.md).
                    .pickerStyle(.navigationLink)
                }
                Section {
                    TextField("Where it is", text: $draft.detail, prompt: Text(detailPrompt), axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Who to call", text: $draft.contact, prompt: Text(contactPrompt))
                } footer: {
                    Text("Never put a combination, PIN or password here. Say who knows it instead.")
                }
            }
            .navigationTitle(place == nil ? "New Place" : "Edit Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCancelButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton(place == nil ? "Add" : "Save") {
                        var saved = draft
                        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.save(saved)
                        onSave?(saved)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var detailPrompt: String {
        switch draft.kind {
        case .safe: "Primary closet, top shelf"
        case .depositBox: "Credit union on Main, key in the desk drawer"
        case .cabinet: "Office, second drawer"
        case .wallet: "Glove box"
        case .person: "Their office"
        case .other: "Where to look"
        }
    }

    private var contactPrompt: String {
        switch draft.kind {
        case .depositBox: "The branch’s phone number"
        case .person: "Their name and number"
        default: "Optional"
        }
    }
}

/// One place: what's kept there, when someone last checked, and Still There.
struct PlaceDetailView: View {
    let placeID: String
    @Environment(\.dismiss) private var dismiss
    @State private var store = TroveStore.shared
    @State private var editing = false
    @State private var confirmsDelete = false

    var body: some View {
        if let place = store.place(placeID) {
            content(place)
        } else {
            ContentUnavailableView("This place was removed", systemImage: "mappin.slash")
                .troveToolbar()
        }
    }

    private func content(_ place: TrovePlace) -> some View {
        let documents = store.documents(inPlace: place.id)
        return TroveScreen(place.name, eyebrow: place.kind.label, subtitle: documents.count == 1 ? "1 original" : "\(documents.count) originals") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    if !place.detail.isEmpty {
                        Label(place.detail, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                    }
                    if !place.contact.isEmpty {
                        Label(place.contact, systemImage: "phone")
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last checked").font(.footnote).foregroundStyle(.secondary)
                            Text(place.confirmedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Not yet")
                                .font(.headline)
                        }
                        Spacer()
                        Button("Everything’s There") { store.confirmPlace(place.id) }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.jade)
                            .disabled(documents.isEmpty)
                    }
                }
            }

            CardLabel("Kept here")
            if documents.isEmpty {
                EmptyCard(systemName: place.kind.symbol, title: "Nothing here yet", message: "Choose this place on a document’s Where the Original Is.")
            } else {
                CardList(items: documents, inset: 62) { document in
                    NavigationLink(value: Destination.document(document.id)) {
                        DocumentRow(document: document, showsOwner: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .refreshable { await store.syncNow() }
        .troveToolbar {
            Button("Edit", systemImage: "pencil") { editing = true }
            Menu("More", systemImage: "ellipsis") {
                Button("Delete Place", menuIcon: "trash", role: .destructive) { confirmsDelete = true }
            }
        }
        .sheet(isPresented: $editing) { PlaceEditor(place: place) }
        .alert("Delete \(place.name)?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deletePlace(place.id)
                dismiss()
            }
        } message: {
            Text(documents.isEmpty ? "This only removes the place from Trove." : "Its \(documents.count == 1 ? "original goes" : "\(documents.count) originals go") back to Not Sure Yet. The documents stay.")
        }
    }
}
