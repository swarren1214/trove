import Foundation

/// What a document is. Drives its symbol, which number it has, how long before it expires Trove
/// starts reminding, whether its paper original matters, and what renewing it takes.
nonisolated enum DocumentType: String, Codable, CaseIterable, Identifiable, Sendable {
    // Identity
    case passport
    case passportCard
    case driversLicense
    case stateID
    case socialSecurityCard
    case birthCertificate
    case marriageCertificate
    case naturalizationCertificate
    // Vehicles
    case vehicleTitle
    case vehicleRegistration
    // Home
    case deed
    case mortgage
    case lease
    case homeWarranty
    // Insurance and coverage
    case insuranceCard
    case insurancePolicy
    case warranty
    // Money and legal
    case will
    case powerOfAttorney
    case taxReturn
    // Everything else
    case receipt
    case manual
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .passport: "Passport"
        case .passportCard: "Passport card"
        case .driversLicense: "Driver’s license"
        case .stateID: "State ID"
        case .socialSecurityCard: "Social Security card"
        case .birthCertificate: "Birth certificate"
        case .marriageCertificate: "Marriage certificate"
        case .naturalizationCertificate: "Naturalization certificate"
        case .vehicleTitle: "Certificate of title"
        case .vehicleRegistration: "Registration"
        case .deed: "Deed"
        case .mortgage: "Mortgage"
        case .lease: "Lease"
        case .homeWarranty: "Home warranty"
        case .insuranceCard: "Insurance card"
        case .insurancePolicy: "Insurance policy"
        case .warranty: "Warranty"
        case .will: "Will or trust"
        case .powerOfAttorney: "Power of attorney"
        case .taxReturn: "Tax return"
        case .receipt: "Receipt"
        case .manual: "Manual"
        case .other: "Other document"
        }
    }

    var symbol: String {
        switch self {
        case .passport, .passportCard: "globe.americas"
        case .driversLicense, .stateID: "person.text.rectangle"
        case .socialSecurityCard: "number.square"
        case .birthCertificate: "figure.and.child.holdinghands"
        case .marriageCertificate: "heart.text.square"
        case .naturalizationCertificate: "flag"
        case .vehicleTitle: "car.rear"
        case .vehicleRegistration: "checkmark.seal"
        case .deed: "house"
        case .mortgage: "building.columns"
        case .lease: "key"
        case .homeWarranty: "wrench.and.screwdriver"
        case .insuranceCard, .insurancePolicy: "shield.lefthalf.filled"
        case .warranty: "checkmark.shield"
        case .will, .powerOfAttorney: "signature"
        case .taxReturn: "doc.text.magnifyingglass"
        case .receipt: "receipt"
        case .manual: "book.closed"
        case .other: "doc"
        }
    }

    /// Groups for pickers and for a person's or asset's documents.
    nonisolated enum Group: String, CaseIterable, Sendable, Identifiable {
        case identity, vehicle, home, coverage, legal, other
        var id: String { rawValue }

        var title: String {
            switch self {
            case .identity: "Identity"
            case .vehicle: "Vehicle"
            case .home: "Home"
            case .coverage: "Insurance and warranties"
            case .legal: "Money and legal"
            case .other: "Other"
            }
        }
    }

    var group: Group {
        switch self {
        case .passport, .passportCard, .driversLicense, .stateID, .socialSecurityCard, .birthCertificate, .marriageCertificate, .naturalizationCertificate: .identity
        case .vehicleTitle, .vehicleRegistration: .vehicle
        case .deed, .mortgage, .lease, .homeWarranty: .home
        case .insuranceCard, .insurancePolicy, .warranty: .coverage
        case .will, .powerOfAttorney, .taxReturn: .legal
        case .receipt, .manual, .other: .other
        }
    }

    /// Who it usually belongs to, for the Add sheet's first guess.
    var usuallyBelongsToPerson: Bool { group == .identity || self == .will || self == .powerOfAttorney }

    /// The name of its number, when it has one worth keeping. Always stored as sensitive.
    var numberLabel: String? {
        switch self {
        case .passport, .passportCard: "Passport number"
        case .driversLicense: "License number"
        case .stateID: "ID number"
        case .socialSecurityCard: "Social Security number"
        case .birthCertificate: "Certificate number"
        case .naturalizationCertificate: "Certificate number"
        case .vehicleTitle: "Title number"
        case .vehicleRegistration: "Registration number"
        case .insuranceCard, .insurancePolicy, .homeWarranty: "Policy number"
        case .warranty: "Serial or contract number"
        case .mortgage: "Loan number"
        default: nil
        }
    }

    /// Whether it expires, so the editor asks for a date.
    var expires: Bool {
        switch self {
        case .passport, .passportCard, .driversLicense, .stateID, .vehicleRegistration, .insuranceCard, .insurancePolicy, .warranty, .homeWarranty, .lease: true
        default: false
        }
    }

    /// Whether the paper original is what counts (it's what offices ask for), so Trove asks
    /// where it's kept and lists it under Location unknown until it knows.
    var originalMatters: Bool {
        switch self {
        case .passport, .passportCard, .socialSecurityCard, .birthCertificate, .marriageCertificate, .naturalizationCertificate,
             .vehicleTitle, .deed, .will, .powerOfAttorney: true
        default: false
        }
    }

    /// How many days before it expires Trove starts reminding, by default.
    var defaultLeadDays: Int {
        switch self {
        // Many countries want six months left on a passport, and renewing takes weeks.
        case .passport, .passportCard: 270
        case .driversLicense, .stateID: 60
        // Time for an emissions or safety inspection where one is needed.
        case .vehicleRegistration: 45
        case .insuranceCard, .insurancePolicy: 30
        case .warranty, .homeWarranty: 60
        case .lease: 90
        default: 30
        }
    }

    /// A short note on what renewing takes, shown on the renewal card. `ownerAge` is the
    /// owner's age when the document is a person's.
    func renewalNote(ownerAge: Int?) -> String? {
        switch self {
        case .passport:
            if let ownerAge, ownerAge < 16 {
                return "Passports for kids under 16 can’t be renewed by mail. Plan an in-person visit with both parents and Form DS-11."
            }
            return "Adults can usually renew by mail or online with Form DS-82. Allow several weeks, more before summer travel."
        case .passportCard:
            return "Renew with your passport book or on its own with Form DS-82."
        case .driversLicense, .stateID:
            return "Many states renew online. Check whether yours needs a visit or a new photo this time."
        case .vehicleRegistration:
            return "Check whether your state needs an inspection first, then renew online or by mail. Put the new sticker on and scan the new card."
        case .insuranceCard, .insurancePolicy:
            return "Your insurer usually sends the new card before this date. Scan it when it arrives."
        case .warranty, .homeWarranty:
            return "Book any covered repairs before it ends, or ask about extending it."
        case .lease:
            return "Decide whether to renew, and check how much notice your lease asks for."
        default:
            return nil
        }
    }

    /// The types in a group, in order.
    static func types(in group: Group) -> [DocumentType] {
        allCases.filter { $0.group == group }
    }
}
