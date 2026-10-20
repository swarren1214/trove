import Foundation
import FoundationModels
import OSLog
import UIKit
import Vision

/// What Trove read from a document's pages. Every field is a suggestion the person confirms in
/// the Add sheet; anything Trove isn't sure of stays empty.
nonisolated struct DocumentReading: Sendable, Equatable {
    var type: DocumentType?
    /// The name printed on it.
    var name: String = ""
    var number: String = ""
    var issuer: String = ""
    /// "YYYY-MM-DD".
    var issuedOn: String?
    var expiresOn: String?
    var birthDate: String?
    /// A vehicle's VIN, from a title, registration or insurance card.
    var vin: String = ""
    /// Where it came from, for the sheet's note: "Read from the barcode".
    var source: Source = .none

    nonisolated enum Source: Sendable, Equatable {
        case none, barcode, machineReadableZone, text
    }

    var isEmpty: Bool { type == nil && name.isEmpty && number.isEmpty && expiresOn == nil }
}

/// Reads documents on the device, in order of how sure it can be:
/// 1. The PDF417 barcode on the back of a US or Canadian driver's license or ID (AAMVA fields).
/// 2. The machine-readable lines at the bottom of a passport's photo page.
/// 3. Everything else: Vision reads the text, then Apple's on-device model says what kind of
///    document it is and picks out the name, number and dates.
/// Nothing leaves the device.
enum DocumentReader {
    private static let log = Logger(subsystem: "com.stephenwarren.trove", category: "reader")

    static var modelIsAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Reads every page and returns the best of what it found.
    static func read(_ pages: [UIImage], expecting type: DocumentType? = nil, today: Date = .now) async -> DocumentReading {
        guard !pages.isEmpty else { return DocumentReading() }
        let scanned = await Task.detached(priority: .userInitiated) { () -> (barcode: DocumentReading?, mrz: DocumentReading?, text: String) in
            var barcode: DocumentReading?
            var mrz: DocumentReading?
            var text: [String] = []
            for page in pages {
                guard let image = page.cgImage else { continue }
                // A photo from the library is often stored sideways with a rotation flag;
                // Vision needs the flag to read it upright.
                let orientation = VisionReading.orientation(of: page)
                if barcode == nil, let payload = VisionReading.pdf417(in: image, orientation: orientation).first {
                    barcode = AAMVA.parse(payload)
                }
                let lines = VisionReading.text(in: image, orientation: orientation)
                if mrz == nil { mrz = MRZ.parse(lines) }
                text.append(contentsOf: lines)
            }
            return (barcode, mrz, text.joined(separator: "\n"))
        }.value

        if let barcode = scanned.barcode, !barcode.isEmpty {
            var reading = barcode
            if reading.type == nil { reading.type = type ?? .driversLicense }
            return reading
        }
        if let mrz = scanned.mrz, !mrz.isEmpty { return mrz }
        return await readText(scanned.text, expecting: type, today: today)
    }

    /// Asks the on-device model what the text is. Without Apple Intelligence, only the type the
    /// person already picked comes back.
    static func readText(_ text: String, expecting type: DocumentType?, today: Date) async -> DocumentReading {
        var fallback = DocumentReading(type: type)
        fallback.vin = VIN.find(in: text) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12, modelIsAvailable else { return fallback }
        let types = DocumentType.allCases.map(\.rawValue).joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
            You read photos of a family's important documents: IDs, certificates, titles, \
            registrations, insurance cards, policies, warranties and receipts. Read names, numbers \
            and dates exactly as printed. Dates are YYYY-MM-DD; today is \
            \(today.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())). \
            Leave a field empty when it isn't printed. Never guess a number.
            """)
        let prompt = """
            \(type.map { "The person says this is a \($0.label.lowercased()).\n" } ?? "")The kinds of document: \(types).

            \(String(trimmed.prefix(3_000)))
            """
        do {
            let reply = try await session.respond(to: prompt, generating: ModelReading.self, options: GenerationOptions(temperature: 0.1)).content
            var reading = DocumentReading(source: .text)
            reading.type = type ?? DocumentType(rawValue: reply.kind)
            reading.name = reply.name.trimmingCharacters(in: .whitespacesAndNewlines)
            reading.number = reply.number.trimmingCharacters(in: .whitespacesAndNewlines)
            reading.issuer = reply.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            reading.issuedOn = Dates.clean(reply.issuedOn)
            reading.expiresOn = Dates.clean(reply.expiresOn)
            reading.vin = VIN.find(in: text) ?? ""
            return reading
        } catch {
            log.error("Reading a document failed: \(String(describing: error), privacy: .public)")
            return fallback
        }
    }
}

/// What the model fills in.
@Generable
nonisolated struct ModelReading {
    @Guide(description: "Which kind of document this is: one of the kinds listed, written exactly as listed. other when none fits.")
    var kind: String

    @Guide(description: "The full name of the person it belongs to, as printed, or empty")
    var name: String

    @Guide(description: "The document's own number (passport number, license number, policy number, certificate number), exactly as printed, or empty")
    var number: String

    @Guide(description: "Who issued it, for example \"U.S. Department of State\", \"Utah DMV\" or \"Geico\", or empty")
    var issuer: String

    @Guide(description: "The issue or effective date as YYYY-MM-DD, or empty")
    var issuedOn: String

    @Guide(description: "The expiration or end date as YYYY-MM-DD, or empty")
    var expiresOn: String
}

// MARK: - Vision

nonisolated enum VisionReading {
    /// Text lines, top to bottom.
    static func text(in image: CGImage, orientation: CGImagePropertyOrientation = .up) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        do { try handler.perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// Where the lines of text are, as fractions of the page with the origin at the top left,
    /// top to bottom. Quick and rough: it's only for the reading animation.
    static func textBoxes(in image: CGImage, orientation: CGImagePropertyOrientation = .up) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        do { try handler.perform([request]) } catch { return [] }
        return (request.results ?? [])
            .map { CGRect(x: $0.boundingBox.minX, y: 1 - $0.boundingBox.maxY, width: $0.boundingBox.width, height: $0.boundingBox.height) }
            .sorted { $0.minY < $1.minY }
    }

    /// PDF417 barcodes' text (the back of a driver's license).
    static func pdf417(in image: CGImage, orientation: CGImagePropertyOrientation = .up) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.pdf417]
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        do { try handler.perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }

    /// The image's rotation flag, as Vision takes it.
    static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

// MARK: - Driver's licenses (AAMVA)

/// The barcode on US and Canadian licenses and IDs: three-letter element IDs, one per line.
nonisolated enum AAMVA {
    static func parse(_ payload: String) -> DocumentReading? {
        guard payload.contains("ANSI") || payload.contains("AAMVA") || payload.contains("DAQ") else { return nil }
        var fields: [String: String] = [:]
        for raw in payload.components(separatedBy: CharacterSet(charactersIn: "\n\r\u{1E}")) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            // A subfile's first element follows its "DL" or "ID" designator, often on the
            // header's line ("…DL00410278…DLDAQD1234567").
            for marker in ["DLDAQ", "IDDAQ", "DLDCA", "IDDCA"] {
                if let range = line.range(of: marker) {
                    line = String(line[line.index(range.lowerBound, offsetBy: 2)...])
                    break
                }
            }
            guard line.count > 3 else { continue }
            let key = String(line.prefix(3))
            if fields[key] == nil { fields[key] = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        }
        guard let number = fields["DAQ"], !number.isEmpty else { return nil }
        let first = fields["DAC"] ?? fields["DCT"] ?? ""
        let middle = fields["DAD"] ?? ""
        let last = fields["DCS"] ?? fields["DAB"] ?? ""
        let name = [first, middle, last]
            .map { $0.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces).capitalized }
            .filter { !$0.isEmpty && $0 != "None" }
            .joined(separator: " ")
        let isID = payload.contains("IDDAQ") || payload.contains("IDDCA")
        let canadian = (fields["DCG"] ?? "").uppercased() == "CAN"
        return DocumentReading(
            type: isID ? .stateID : .driversLicense,
            name: name,
            number: number,
            issuer: fields["DAJ"].map { "\($0) DMV" } ?? "",
            issuedOn: date(fields["DBD"], canadian: canadian),
            expiresOn: date(fields["DBA"], canadian: canadian),
            birthDate: date(fields["DBB"], canadian: canadian),
            source: .barcode
        )
    }

    /// US cards write MMDDCCYY, Canadian ones CCYYMMDD.
    private static func date(_ raw: String?, canadian: Bool) -> String? {
        guard let raw, raw.count == 8, raw.allSatisfy(\.isNumber) else { return nil }
        let digits = Array(raw)
        let (year, month, day) = canadian
            ? (String(digits[0..<4]), String(digits[4..<6]), String(digits[6..<8]))
            : (String(digits[4..<8]), String(digits[0..<2]), String(digits[2..<4]))
        return Dates.clean("\(year)-\(month)-\(day)")
    }
}

// MARK: - Passports (machine-readable zone)

/// The two 44-character lines at the bottom of a passport's photo page (ICAO 9303, TD3).
nonisolated enum MRZ {
    static func parse(_ lines: [String]) -> DocumentReading? {
        let cleaned = lines.map { $0.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "«", with: "<") }
        guard let index = cleaned.firstIndex(where: { $0.hasPrefix("P") && $0.count >= 40 && $0.contains("<<") }),
              index + 1 < cleaned.count else { return nil }
        let line1 = Array(cleaned[index].padding(toLength: 44, withPad: "<", startingAt: 0))
        let line2 = Array(cleaned[index + 1].padding(toLength: 44, withPad: "<", startingAt: 0))
        guard line2.count >= 28 else { return nil }

        let names = String(line1[5..<44]).components(separatedBy: "<<")
        let surname = names.first?.replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces) ?? ""
        let given = names.dropFirst().first?.replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces) ?? ""
        let number = String(line2[0..<9]).replacingOccurrences(of: "<", with: "")
        guard !number.isEmpty, checkDigit(String(line2[0..<9])) == String(line2[9]) else { return nil }
        let country = String(line1[2..<5]).replacingOccurrences(of: "<", with: "")
        return DocumentReading(
            type: .passport,
            name: [given, surname].filter { !$0.isEmpty }.map(\.capitalized).joined(separator: " "),
            number: number,
            issuer: country == "USA" ? "U.S. Department of State" : country,
            issuedOn: nil,
            expiresOn: date(String(line2[21..<27]), future: true),
            birthDate: date(String(line2[13..<19]), future: false),
            source: .machineReadableZone
        )
    }

    /// YYMMDD: expiry dates are in the next few decades, birthdays in the past.
    private static func date(_ raw: String, future: Bool) -> String? {
        guard raw.count == 6, raw.allSatisfy(\.isNumber), let yy = Int(raw.prefix(2)) else { return nil }
        let thisYear = Calendar.current.component(.year, from: .now) % 100
        let century = future ? (yy + 20 < thisYear ? 2100 : 2000) : (yy > thisYear ? 1900 : 2000)
        let digits = Array(raw)
        return Dates.clean("\(century + yy)-\(String(digits[2..<4]))-\(String(digits[4..<6]))")
    }

    /// The 7-3-1 check digit.
    private static func checkDigit(_ field: String) -> String {
        let weights = [7, 3, 1]
        var sum = 0
        for (index, character) in field.enumerated() {
            let value: Int
            if let digit = character.wholeNumberValue {
                value = digit
            } else if let ascii = character.asciiValue, character.isLetter {
                value = Int(ascii) - 55
            } else {
                value = 0
            }
            sum += value * weights[index % 3]
        }
        return String(sum % 10)
    }
}

// MARK: - Small helpers

nonisolated enum VIN {
    /// A 17-character VIN in the text (no I, O or Q).
    static func find(in text: String) -> String? {
        let pattern = #/\b[A-HJ-NPR-Z0-9]{17}\b/#
        return text.uppercased().firstMatch(of: pattern).map { String($0.output) }
    }
}

nonisolated enum Dates {
    /// "YYYY-MM-DD" when it's a real date, otherwise nil.
    static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), text.count >= 10 else { return nil }
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1900...2200).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]),
              let date = HearthDay.date(from: String(text.prefix(10))),
              Calendar.current.component(.day, from: date) == parts[2] else { return nil }
        return HearthDay.string(from: date)
    }
}
