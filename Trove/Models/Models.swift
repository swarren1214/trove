import Foundation

// Trove's data, as the vault keeps it: in the family's iCloud (the Hearth container's Trove zone,
// shared with the household's parents and adults) with a copy on the device. Each value is one
// CloudKit record; the newest `updatedAt` wins. Content is end-to-end encrypted
// (`encryptedValues`); scans are CloudKit assets.

// MARK: - Assets

nonisolated enum AssetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case vehicle, home, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vehicle: "Vehicle"
        case .home: "Home"
        case .other: "Other"
        }
    }

    /// "Vehicles", "Homes", "Other".
    var pluralLabel: String {
        switch self {
        case .vehicle: "Vehicles"
        case .home: "Homes"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .vehicle: "car.side"
        case .home: "house"
        case .other: "shippingbox"
        }
    }

    /// The facts the editor asks for, in order.
    var factKeys: [AssetFact.Key] {
        switch self {
        case .vehicle: [.year, .make, .model, .vin, .plate, .insurer, .lienholder]
        case .home: [.address, .insurer, .lender]
        case .other: [.maker, .model, .serial, .purchased]
        }
    }

    /// The document types an asset of this kind usually has, for "Add" suggestions.
    var usualDocuments: [DocumentType] {
        switch self {
        case .vehicle: [.vehicleTitle, .vehicleRegistration, .insuranceCard, .warranty]
        case .home: [.deed, .mortgage, .insurancePolicy, .homeWarranty]
        case .other: [.receipt, .warranty, .manual]
        }
    }
}

/// One thing known about an asset: its VIN, its address.
nonisolated struct AssetFact: Codable, Hashable, Sendable, Identifiable {
    nonisolated enum Key: String, Codable, Sendable {
        case year, make, model, vin, plate, insurer, lienholder
        case address, lender
        case maker, serial, purchased

        var label: String {
            switch self {
            case .year: "Year"
            case .make: "Make"
            case .model: "Model"
            case .vin: "VIN"
            case .plate: "Plate"
            case .insurer: "Insurer"
            case .lienholder: "Lienholder"
            case .address: "Address"
            case .lender: "Lender"
            case .maker: "Made by"
            case .serial: "Serial number"
            case .purchased: "Purchased"
            }
        }

        /// Shown masked until Face ID.
        var isSensitive: Bool { self == .vin || self == .serial }

        var usesMonospace: Bool { self == .vin || self == .plate || self == .serial }
    }

    var key: Key
    var value: String
    var id: String { key.rawValue }
}

nonisolated struct TroveAsset: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var kind: AssetKind
    var name: String
    var facts: [AssetFact] = []
    var notes: String = ""
    var createdAt: Date = .now
    var updatedAt: Date = .now

    func fact(_ key: AssetFact.Key) -> String? {
        let value = facts.first { $0.key == key }?.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    mutating func setFact(_ key: AssetFact.Key, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.removeAll { $0.key == key }
        if !trimmed.isEmpty { facts.append(AssetFact(key: key, value: trimmed)) }
    }
}

// MARK: - Documents

/// Who or what a document belongs to.
nonisolated enum DocumentOwner: Codable, Hashable, Sendable {
    /// A person in the Hearth household, by their household id.
    case person(String)
    case asset(String)
    /// The whole household (a will, a home warranty with no home added).
    case household

    var personID: String? {
        if case .person(let id) = self { return id }
        return nil
    }

    var assetID: String? {
        if case .asset(let id) = self { return id }
        return nil
    }
}

/// A photo of a page, exactly as it was captured. The image file lives on the device
/// (`TroveFiles.scanURL`) and in iCloud as its own record.
nonisolated struct TroveScan: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    /// "Front", "Back", "Page 2".
    var label: String
    var capturedAt: Date = .now
    /// "Camera", "Photos", "Files".
    var source: String
    var width: Int
    var height: Int

    var fileName: String { "\(id).jpg" }
}

nonisolated struct TroveDocument: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var type: DocumentType
    /// What it's called on screen: "Ava’s passport". Empty uses the type's name.
    var title: String = ""
    var owner: DocumentOwner = .household
    /// The name printed on it, as read (for matching to a person later).
    var nameOnDocument: String = ""
    /// The document's number. Sensitive: masked until Face ID, never in search, logs or
    /// notifications.
    var number: String = ""
    /// Who issued it: "U.S. Department of State", "Geico".
    var issuer: String = ""
    /// "YYYY-MM-DD".
    var issuedOn: String?
    var expiresOn: String?
    /// Days before expiring to start reminding; nil uses the type's default.
    var leadDays: Int?
    var scans: [TroveScan] = []
    /// Where the paper original is kept; nil when nobody knows yet.
    var placeID: String?
    /// "Top shelf", "Blue folder".
    var placeDetail: String = ""
    /// Someone saw the original there.
    var originalConfirmedAt: Date?
    /// There's no paper original (a digital card, an email), so it's never "Location unknown".
    var noOriginal = false
    var notes: String = ""
    var createdAt: Date = .now
    var updatedAt: Date = .now

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? type.label : trimmed
    }

    var issuedDate: Date? { issuedOn.flatMap { HearthDay.date(from: $0) } }
    var expiryDate: Date? { expiresOn.flatMap { HearthDay.date(from: $0) } }
    var effectiveLeadDays: Int { leadDays ?? type.defaultLeadDays }

    var hasNumber: Bool { !number.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The original's location is unknown and it matters.
    var originalIsMissing: Bool { placeID == nil && !noOriginal && type.originalMatters }
}

// MARK: - Places

nonisolated enum PlaceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case safe, depositBox, cabinet, wallet, person, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .safe: "Safe"
        case .depositBox: "Safe deposit box"
        case .cabinet: "Filing cabinet or drawer"
        case .wallet: "Wallet or car"
        case .person: "With someone"
        case .other: "Somewhere else"
        }
    }

    var symbol: String {
        switch self {
        case .safe: "lock.square"
        case .depositBox: "building.columns"
        case .cabinet: "cabinet"
        case .wallet: "wallet.bifold"
        case .person: "person.badge.shield.checkmark"
        case .other: "mappin"
        }
    }
}

/// Where paper originals are kept.
nonisolated struct TrovePlace: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var kind: PlaceKind
    /// "Primary closet, top shelf", "Key in the desk drawer".
    var detail: String = ""
    /// Who to call: the attorney's office, the credit union branch.
    var contact: String = ""
    /// Someone checked everything was still there.
    var confirmedAt: Date?
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

// MARK: - Everything

/// Everything in one vault, as saved on the device.
nonisolated struct TroveState: Codable, Hashable, Sendable {
    var assets: [String: TroveAsset] = [:]
    var documents: [String: TroveDocument] = [:]
    var places: [String: TrovePlace] = [:]

    var isEmpty: Bool { assets.isEmpty && documents.isEmpty && places.isEmpty }
}
