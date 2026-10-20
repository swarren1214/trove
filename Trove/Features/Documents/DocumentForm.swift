import SwiftUI

/// What the Add and Edit sheets change, before it's saved.
struct DocumentDraft: Equatable {
    var type: DocumentType
    var title: String = ""
    var owner: DocumentOwner = .household
    var nameOnDocument: String = ""
    var number: String = ""
    var issuer: String = ""
    var issued: Date?
    var expires: Date?
    var leadDays: Int?
    var placeID: String?
    var placeDetail: String = ""
    var noOriginal = false
    var notes: String = ""

    init(type: DocumentType, owner: DocumentOwner = .household) {
        self.type = type
        self.owner = owner
    }

    init(_ document: TroveDocument) {
        type = document.type
        title = document.title
        owner = document.owner
        nameOnDocument = document.nameOnDocument
        number = document.number
        issuer = document.issuer
        issued = document.issuedDate
        expires = document.expiryDate
        leadDays = document.leadDays
        placeID = document.placeID
        placeDetail = document.placeDetail
        noOriginal = document.noOriginal
        notes = document.notes
    }

    /// The document with these changes.
    func applied(to document: TroveDocument) -> TroveDocument {
        var document = document
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if document.placeID != placeID { document.originalConfirmedAt = placeID == nil ? nil : .now }
        document.type = type
        document.title = clean(title)
        document.owner = owner
        document.nameOnDocument = clean(nameOnDocument)
        document.number = clean(number)
        document.issuer = clean(issuer)
        document.issuedOn = issued.map { HearthDay.string(from: $0) }
        document.expiresOn = expires.map { HearthDay.string(from: $0) }
        document.leadDays = leadDays
        document.placeID = placeID
        document.placeDetail = placeID == nil ? "" : clean(placeDetail)
        document.noOriginal = placeID == nil && noOriginal
        document.notes = clean(notes)
        return document
    }

    /// Fills in what was read, without overwriting anything the person already typed.
    mutating func take(_ reading: DocumentReading, household: HearthHouseholdStore, store: TroveStore, typeWasChosen: Bool) {
        if !typeWasChosen, let type = reading.type { self.type = type }
        if nameOnDocument.isEmpty { nameOnDocument = reading.name }
        if number.isEmpty { number = reading.number }
        if issuer.isEmpty { issuer = reading.issuer }
        if issued == nil { issued = reading.issuedOn.flatMap { HearthDay.date(from: $0) } }
        if expires == nil { expires = reading.expiresOn.flatMap { HearthDay.date(from: $0) } }
        // Whose is it? A name on the document that matches someone in the household, or a VIN
        // that matches a vehicle.
        if owner == .household {
            if !reading.name.isEmpty, let person = Self.match(reading.name, in: household.people) {
                owner = .person(person.id)
            } else if !reading.vin.isEmpty, let vehicle = store.assets.first(where: { $0.fact(.vin)?.uppercased() == reading.vin }) {
                owner = .asset(vehicle.id)
            }
        }
    }

    /// The household person whose name matches: the full name, or a first name only one person has.
    static func match(_ name: String, in people: [HearthMember]) -> HearthMember? {
        let wanted = HearthNames.normalized(name)
        if let exact = people.first(where: { HearthNames.normalized($0.name) == wanted }) { return exact }
        let words = Set(wanted.split(separator: " ").map(String.init))
        let firstMatches = people.filter { words.contains(HearthNames.firstName(HearthNames.normalized($0.name))) }
        return firstMatches.count == 1 ? firstMatches.first : nil
    }
}

/// The fields of a document, shared by the Add and Edit sheets.
struct DocumentFormSections: View {
    @Binding var draft: DocumentDraft
    @State private var household = HearthHouseholdStore.shared
    @State private var store = TroveStore.shared
    @State private var addingPlace = false

    var body: some View {
        Section {
            Picker("Type", selection: $draft.type) {
                ForEach(DocumentType.Group.allCases) { group in
                    Section(group.title) {
                        ForEach(DocumentType.types(in: group)) { type in
                            Text(type.label).tag(type)
                        }
                    }
                }
            }
            .pickerStyle(.navigationLink)
            Picker("Belongs to", selection: $draft.owner) {
                Section("People") {
                    ForEach(household.people) { person in
                        Text(person.trimmedName).tag(DocumentOwner.person(person.id))
                    }
                }
                if !store.assets.isEmpty {
                    Section("Assets") {
                        ForEach(store.assets) { asset in
                            Text(asset.name).tag(DocumentOwner.asset(asset.id))
                        }
                    }
                }
                Text(household.info?.name ?? "The household").tag(DocumentOwner.household)
            }
            .pickerStyle(.navigationLink)
            TextField("Title", text: $draft.title, prompt: Text("Title (optional)"))
        }

        Section {
            if let label = draft.type.numberLabel {
                TextField(label, text: $draft.number)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .privacySensitive()
            }
            TextField("Name on it", text: $draft.nameOnDocument)
                .textInputAutocapitalization(.words)
            TextField("Issued by", text: $draft.issuer)
            OptionalDateRow(title: "Issued", date: $draft.issued)
            if draft.type.expires || draft.expires != nil {
                OptionalDateRow(title: "Expires", date: $draft.expires, isFuture: true)
            }
        } footer: {
            if draft.type.numberLabel != nil {
                Text("The number stays hidden until someone unlocks it with Face ID. It’s never searched or put in a notification.")
            }
        }

        if draft.expires != nil {
            Section {
                Picker("Remind me", selection: $draft.leadDays) {
                    Text("\(Self.leadLabel(draft.type.defaultLeadDays)) before (suggested)").tag(Int?.none)
                    ForEach(Self.leadChoices.filter { $0 != draft.type.defaultLeadDays }, id: \.self) { days in
                        Text("\(Self.leadLabel(days)) before").tag(Int?.some(days))
                    }
                }
                // A list with the checkmark on the right, not a menu (see AGENT.md).
                .pickerStyle(.navigationLink)
            } footer: {
                if let note = draft.type.renewalNote(ownerAge: household.member(draft.owner.personID)?.age()) {
                    Text(note)
                }
            }
        }

        Section {
            NavigationLink {
                Form {
                    Section {
                        PlaceChoices(selection: $draft.placeID, noOriginal: $draft.noOriginal)
                        Button("New Place", systemImage: "plus") { addingPlace = true }
                    }
                    if draft.placeID != nil {
                        Section("Exactly where") {
                            TextField("Top shelf, blue folder", text: $draft.placeDetail)
                        }
                    }
                }
                .navigationTitle("Original Kept In")
                .sheet(isPresented: $addingPlace) {
                    PlaceEditor(place: nil) { added in
                        draft.placeID = added.id
                        draft.noOriginal = false
                    }
                }
            } label: {
                LabeledContent("Original kept in", value: placeValue)
            }
        } footer: {
            if draft.type.originalMatters {
                Text("Offices usually want the original \(draft.type.label.localizedLowercase), so Trove keeps track of where it is.")
            }
        }

        Section("Notes") {
            TextField("Anything worth knowing", text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var placeValue: String {
        if let place = store.place(draft.placeID) { return place.name }
        return draft.noOriginal ? "No paper original" : "Not sure yet"
    }

    static let leadChoices = [7, 14, 30, 45, 60, 90, 180, 270]

    static func leadLabel(_ days: Int) -> String {
        switch days {
        case 7: "1 week"
        case 14: "2 weeks"
        case 30: "1 month"
        case 45: "6 weeks"
        case 60: "2 months"
        case 90: "3 months"
        case 180: "6 months"
        case 270: "9 months"
        default: "\(days) days"
        }
    }
}

/// A date that may not be known: "Add" until there is one, then a date picker with a way back.
struct OptionalDateRow: View {
    var title: String
    @Binding var date: Date?
    var isFuture = false

    var body: some View {
        if let value = date {
            HStack {
                DatePicker(title, selection: Binding(get: { value }, set: { date = $0 }), displayedComponents: .date)
                Button("Clear \(title)", systemImage: "xmark.circle.fill") { date = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
            }
        } else {
            Button {
                date = isFuture ? Calendar.current.date(byAdding: .year, value: 1, to: .now) : .now
            } label: {
                LabeledContent(title) {
                    Text("Add").foregroundStyle(Brand.ink)
                }
            }
            .foregroundStyle(.primary)
        }
    }
}
