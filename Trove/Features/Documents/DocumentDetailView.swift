import SwiftUI

/// One document, from the Trove canvas: the card with its dates, its number behind Face ID, the
/// original scans exactly as captured, where the paper original is, what renewing takes when
/// it's coming due, and Present, Share Copy and Export PDF.
struct DocumentDetailView: View {
    let documentID: String
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var store = TroveStore.shared
    @State private var editing = false
    @State private var choosingPlace = false
    @State private var viewing: TroveScan?
    @State private var presenting = false

    var body: some View {
        if let document = store.document(documentID) {
            content(document)
        } else {
            ContentUnavailableView("This document was removed", systemImage: "doc")
                .troveToolbar()
        }
    }

    private func content(_ document: TroveDocument) -> some View {
        TroveScreen(Attention.title(of: document), largeTitle: false) {
            DocumentHeroCard(document: document, ownerName: ownerLine(document))

            if document.hasNumber || !document.nameOnDocument.isEmpty || document.type.numberLabel != nil {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        if let label = document.type.numberLabel {
                            FactRow(label: "Number", isLast: document.nameOnDocument.isEmpty && validityLine(document) == nil) {
                                if document.hasNumber {
                                    SecureValue(value: document.number, reason: "Show the \(label.localizedLowercase)")
                                } else {
                                    Button("Add") { editing = true }
                                        .foregroundStyle(Brand.ink)
                                }
                            }
                        }
                        if !document.nameOnDocument.isEmpty {
                            FactRow("Name on it", value: document.nameOnDocument, isLast: validityLine(document) == nil)
                        }
                        if let validity = validityLine(document) {
                            FactRow("Valid for", value: validity, isLast: true)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            scansCard(document)
            originalCard(document)
            if let renewalCard = renewal(document) { renewalCard }

            actions(document)

            if !document.notes.isEmpty {
                CardLabel("Notes")
                Card { Text(document.notes).font(.subheadline).textSelection(.enabled) }
            }
        }
        .refreshable { await store.syncNow() }
        .troveToolbar {
            Button("Edit", systemImage: "pencil") { editing = true }
        }
        .sheet(isPresented: $editing) {
            DocumentEditor(document: document) { dismiss() }
        }
        .sheet(isPresented: $choosingPlace) {
            PlacePicker(document: document)
        }
        .fullScreenCover(item: $viewing) { scan in
            ScanViewer(document: document, start: scan)
        }
        .fullScreenCover(isPresented: $presenting) {
            PresentView(document: document)
        }
    }

    // MARK: Pieces

    private func ownerLine(_ document: TroveDocument) -> String {
        if !document.nameOnDocument.isEmpty { return document.nameOnDocument }
        if let person = store.household.member(document.owner.personID) { return person.trimmedName }
        return store.ownerName(document.owner)
    }

    /// "5 years (issued under 16)" for a passport.
    private func validityLine(_ document: TroveDocument) -> String? {
        guard let issued = document.issuedDate, let expiry = document.expiryDate else { return nil }
        let years = Calendar.current.dateComponents([.year], from: issued, to: Calendar.current.date(byAdding: .day, value: 2, to: expiry) ?? expiry).year ?? 0
        guard years > 0 else { return nil }
        var line = years == 1 ? "1 year" : "\(years) years"
        if document.type == .passport, years == 5, let person = store.household.member(document.owner.personID), let age = person.age(on: issued), age < 16 {
            line += " (issued under 16)"
        }
        return line
    }

    private func scansCard(_ document: TroveDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(title: "Original scans", symbol: "photo.on.rectangle") {
                Button(document.scans.isEmpty ? "Scan" : "Rescan") {
                    router.add(AddDocumentRequest(owner: document.owner, type: document.type, scanFirst: true, documentID: document.id))
                }
                .font(.subheadline)
                .foregroundStyle(Brand.ink)
            }
            Card {
                if document.scans.isEmpty {
                    VStack(spacing: 8) {
                        Text("No scan yet")
                            .font(.headline)
                        Text("Scan it so you have a copy wherever you are.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 12) {
                            ForEach(document.scans) { scan in
                                Button { viewing = scan } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ScanThumbnail(scan: scan, symbol: document.type.symbol, width: 130, height: 104)
                                            .frame(maxWidth: .infinity)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(scan.label).font(.subheadline.weight(.medium))
                                            Text("\(scan.capturedAt.formatted(.dateTime.month(.abbreviated).day().year())) · \(scan.source)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(scan.label), captured \(scan.capturedAt.formatted(date: .abbreviated, time: .omitted))")
                                .accessibilityHint("Opens it full size")
                            }
                        }
                        Text("Tap to view full size. Photos are kept exactly as captured, beside the details read from them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func originalCard(_ document: TroveDocument) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel("Where the original is", symbol: "mappin.and.ellipse")
                    .padding(.horizontal, -4)
                if let place = store.place(document.placeID) {
                    HStack(spacing: 12) {
                        Button { choosingPlace = true } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.headline).foregroundStyle(.primary)
                                Text(placeLine(document, place))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Changes where it’s kept")
                        Spacer(minLength: 8)
                        Button("Still There") { store.confirmOriginal(document.id) }
                            .buttonStyle(.bordered)
                            .tint(Brand.jade)
                            .font(.subheadline.weight(.semibold))
                    }
                } else if document.noOriginal {
                    Text("There’s no paper original for this one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not sure yet").font(.headline)
                            Text(document.type.originalMatters ? "Offices usually want the original. Found it? Say where it lives." : "Add where it’s kept, if there’s a paper copy.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Choose") { choosingPlace = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.jade)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private func placeLine(_ document: TroveDocument, _ place: TrovePlace) -> String {
        var parts: [String] = []
        let detail = document.placeDetail.isEmpty ? place.detail : document.placeDetail
        if !detail.isEmpty { parts.append(detail) }
        if let confirmed = document.originalConfirmedAt ?? place.confirmedAt {
            parts.append("confirmed \(confirmed.formatted(.dateTime.month(.abbreviated).day()))")
        } else {
            parts.append("not checked yet")
        }
        return parts.joined(separator: " · ")
    }

    /// The amber card when it's time to renew.
    private func renewal(_ document: TroveDocument) -> AnyView? {
        guard let expiry = document.expiryDate else { return nil }
        let days = Attention.daysUntil(expiry)
        guard days <= document.effectiveLeadDays else { return nil }
        let urgency: Urgency = days < 0 ? .now : Attention.urgency(days: days, lead: document.effectiveLeadDays)
        let age = store.household.member(document.owner.personID)?.age()
        let note = document.type.renewalNote(ownerAge: age)
        let deadline = Calendar.current.date(byAdding: .day, value: -30, to: expiry) ?? expiry
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(days < 0 ? "Expired \(expiry.formatted(.dateTime.month(.wide).day()))" : "Renew by \(deadline.formatted(.dateTime.month(.wide).day()))")
                        .font(.headline)
                    Spacer()
                    Text(days < 0 ? "\(-days) days ago" : (days == 1 ? "1 day left" : "\(days) days left"))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(urgency.ink)
                if let note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 16) {
                    Button("Scan the New One") {
                        router.add(AddDocumentRequest(owner: document.owner, type: document.type, scanFirst: true))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(urgency.ink)
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(urgency.fill, in: .rect(cornerRadius: 22))
        )
    }

    private func actions(_ document: TroveDocument) -> some View {
        let title = Attention.title(of: document)
        return HStack(spacing: 10) {
            Button { presenting = true } label: {
                actionLabel("Present", "rectangle.portrait.on.rectangle.portrait.angled")
            }
            // Native sharing: the PDF is made only when someone picks where it goes.
            ShareLink(item: TroveExport.document(document, title: title, watermark: true), preview: SharePreview("Copy of \(title)")) {
                actionLabel("Share Copy", "square.and.arrow.up")
            }
            ShareLink(item: TroveExport.document(document, title: title, watermark: false), preview: SharePreview(title)) {
                actionLabel("Export PDF", "doc.richtext")
            }
        }
        .buttonStyle(.plain)
        .disabled(document.scans.isEmpty)
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
    }
}
