import Foundation

/// Something Trove wants someone to look at: a document expiring or expired, an original
/// nobody can find, a place nobody has checked in a year.
struct AttentionItem: Identifiable, Hashable {
    enum Kind: Hashable { case expired, expiring, originalMissing, placeUnchecked }

    var id: String
    var kind: Kind
    var title: String
    var detail: String
    var chip: String?
    var urgency: Urgency
    var symbol: String
    var documentID: String?
    var placeID: String?
    /// For ordering: the expiry date, or far off for the rest.
    var sortDate: Date
}

@MainActor
enum Attention {
    /// Everything that needs a look, most urgent first.
    static func items(store: TroveStore = .shared, now: Date = .now, calendar: Calendar = .current) -> [AttentionItem] {
        var items: [AttentionItem] = []
        for document in store.documents {
            if let expiry = document.expiryDate {
                let days = daysUntil(expiry, from: now, calendar: calendar)
                if days < 0 {
                    items.append(AttentionItem(
                        id: "expired-\(document.id)",
                        kind: .expired,
                        title: title(of: document, store: store),
                        detail: "Expired \(expiry.formatted(.dateTime.month(.abbreviated).day().year()))",
                        chip: "Expired",
                        urgency: .now,
                        symbol: document.type.symbol,
                        documentID: document.id,
                        sortDate: expiry
                    ))
                } else if days <= document.effectiveLeadDays {
                    items.append(AttentionItem(
                        id: "expiring-\(document.id)",
                        kind: .expiring,
                        title: title(of: document, store: store),
                        detail: "Expires \(expiry.formatted(.dateTime.month(.abbreviated).day()))" + (document.type.renewalNote(ownerAge: nil) == nil ? "" : " · time to renew"),
                        chip: chip(days: days),
                        urgency: urgency(days: days, lead: document.effectiveLeadDays),
                        symbol: document.type.symbol,
                        documentID: document.id,
                        sortDate: expiry
                    ))
                }
            }
        }
        let missing = store.documentsWithoutOriginal
        if !missing.isEmpty {
            let names = missing.prefix(3).map { title(of: $0, store: store) }
            items.append(AttentionItem(
                id: "originals",
                kind: .originalMissing,
                title: missing.count == 1 ? "1 original with no location" : "\(missing.count) originals with no location",
                detail: names.formatted(.list(type: .and)) + (missing.count > 3 ? " and more" : ""),
                chip: nil,
                urgency: .calm,
                symbol: "questionmark.circle",
                sortDate: .distantFuture
            ))
        }
        for place in store.places {
            let checked = place.confirmedAt ?? place.createdAt
            guard !store.documents(inPlace: place.id).isEmpty,
                  let due = calendar.date(byAdding: .year, value: 1, to: checked), due < now else { continue }
            items.append(AttentionItem(
                id: "place-\(place.id)",
                kind: .placeUnchecked,
                title: "Check the \(place.name.localizedLowercase)",
                detail: place.confirmedAt == nil ? "Nobody has checked it since it was added" : "Last checked \(checked.formatted(.dateTime.month(.abbreviated).year()))",
                chip: nil,
                urgency: .calm,
                symbol: place.kind.symbol,
                placeID: place.id,
                sortDate: .distantFuture
            ))
        }
        return items.sorted { a, b in
            if a.urgency != b.urgency { return a.urgency > b.urgency }
            return a.sortDate < b.sortDate
        }
    }

    /// "Ava’s passport", or the document's own title when it isn't a person's.
    static func title(of document: TroveDocument, store: TroveStore = .shared) -> String {
        if !document.title.trimmingCharacters(in: .whitespaces).isEmpty { return document.displayTitle }
        switch document.owner {
        case .person(let id):
            if let name = store.household.member(id)?.firstName, !name.isEmpty {
                return "\(name)’s \(document.type.label.localizedLowercase)"
            }
        case .asset(let id):
            if let asset = store.asset(id) { return "\(asset.name) \(document.type.label.localizedLowercase)" }
        case .household:
            break
        }
        return document.type.label
    }

    static func daysUntil(_ date: Date, from now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// "12 days", "6 wk", "5 mo".
    static func chip(days: Int) -> String {
        if days == 0 { return "Today" }
        if days < 14 { return days == 1 ? "1 day" : "\(days) days" }
        if days < 70 { return "\(days / 7) wk" }
        return "\(max(2, Int((Double(days) / 30.4).rounded()))) mo"
    }

    /// Red in the last month (or the last quarter of the lead time), amber before that.
    static func urgency(days: Int, lead: Int) -> Urgency {
        days <= max(30, lead / 4) ? .now : .soon
    }

    /// A document's expiry state for its rows: "Expires Mar 14, 2027", with urgency.
    static func expiryLine(_ document: TroveDocument, now: Date = .now) -> (text: String, urgency: Urgency)? {
        guard let expiry = document.expiryDate else { return nil }
        let days = daysUntil(expiry, from: now)
        let date = expiry.formatted(.dateTime.month(.abbreviated).day().year())
        if days < 0 { return ("Expired \(date)", .now) }
        if days <= document.effectiveLeadDays { return ("Expires \(date)", urgency(days: days, lead: document.effectiveLeadDays)) }
        return ("Expires \(date)", .calm)
    }
}
