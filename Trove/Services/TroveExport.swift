import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

/// PDFs Trove makes, handed to the system share sheet through `ShareLink` (each is made only
/// when someone actually shares it): one document's scans (with a "Copy shared from Trove" line
/// along the bottom when it's a copy for someone else), everything (Profile › Export Everything,
/// always free, behind Face ID), and the emergency packet (what exists and where, with no scans
/// and no numbers).
@MainActor
enum TroveExport {
    /// A document's pages, one per page, under its title.
    static func document(_ document: TroveDocument, title: String, watermark: Bool) -> PDFExport {
        let pages = document.scans.map { TroveFiles.scanURL($0) }
        let footer = watermark ? "Copy shared from Trove on \(Date.now.formatted(date: .long, time: .omitted)). Not the original." : nil
        let name = fileName(title)
        return PDFExport(title: title) {
            guard let url = Renderer.pages(title: title, images: pages, footer: footer, fileName: name) else { throw PDFExport.Failure.couldNotMake }
            return url
        }
    }

    /// Every document: an index page, then each document's pages. Asks for Face ID first, since
    /// it holds every number.
    static func everything(store: TroveStore = .shared) -> PDFExport {
        let sections = store.documents.map { document in
            Renderer.Section(
                title: Attention.title(of: document, store: store),
                lines: lines(for: document, store: store, includeNumber: true),
                images: document.scans.map { TroveFiles.scanURL($0) }
            )
        }
        let name = "Trove Export \(Date.now.formatted(.iso8601.year().month().day()))"
        return PDFExport(title: "Trove export") {
            guard await AppLock.confirm("Export every document") else { throw PDFExport.Failure.notConfirmed }
            guard let url = Renderer.book(title: "Trove export", subtitle: "Everything in Trove on \(Date.now.formatted(date: .long, time: .omitted))", sections: sections, fileName: name) else {
                throw PDFExport.Failure.couldNotMake
            }
            return url
        }
    }

    /// What exists and where: for someone you trust, in an emergency. No scans, no numbers.
    static func emergencyPacket(store: TroveStore = .shared) -> PDFExport {
        var sections: [Renderer.Section] = []
        for place in store.places {
            let documents = store.documents(inPlace: place.id)
            guard !documents.isEmpty else { continue }
            var lines = documents.map { "• " + Attention.title(of: $0, store: store) + (($0.placeDetail.isEmpty) ? "" : " (\($0.placeDetail))") }
            if !place.detail.isEmpty { lines.insert("Where: \(place.detail)", at: 0) }
            if !place.contact.isEmpty { lines.insert("Contact: \(place.contact)", at: 0) }
            sections.append(Renderer.Section(title: place.name, lines: lines, images: []))
        }
        let unknown = store.documents.filter { $0.placeID == nil && !$0.noOriginal }
        if !unknown.isEmpty {
            sections.append(Renderer.Section(title: "Not sure where", lines: unknown.map { "• " + Attention.title(of: $0, store: store) }, images: []))
        }
        let household = store.household.info?.name ?? "Our family"
        let title = "\(household): important documents"
        return PDFExport(title: "Emergency packet") {
            guard let url = Renderer.book(
                title: title,
                subtitle: "Where each original is kept, as of \(Date.now.formatted(date: .long, time: .omitted)). Copies of most are in Trove on our iPhones.",
                sections: sections,
                fileName: "Emergency Packet"
            ) else { throw PDFExport.Failure.couldNotMake }
            return url
        }
    }

    private static func lines(for document: TroveDocument, store: TroveStore, includeNumber: Bool) -> [String] {
        var lines = ["Type: \(document.type.label)", "Belongs to: \(store.ownerName(document.owner))"]
        if includeNumber, document.hasNumber { lines.append("Number: \(document.number)") }
        if let issued = document.issuedDate { lines.append("Issued: \(issued.formatted(date: .long, time: .omitted))") }
        if let expiry = document.expiryDate { lines.append("Expires: \(expiry.formatted(date: .long, time: .omitted))") }
        if let place = store.place(document.placeID) {
            lines.append("Original: \(place.name)" + (document.placeDetail.isEmpty ? "" : ", \(document.placeDetail)"))
        }
        if !document.notes.isEmpty { lines.append("Notes: \(document.notes)") }
        return lines
    }

    nonisolated static func fileName(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Document" : cleaned
    }

    /// Deletes PDFs made earlier (they hold sensitive pages; nothing keeps them).
    static func cleanUp() {
        try? FileManager.default.removeItem(at: Renderer.folder)
    }
}

/// A PDF for `ShareLink`, made off the main thread when the share sheet asks for it.
nonisolated struct PDFExport: Transferable, Sendable {
    enum Failure: Error { case couldNotMake, notConfirmed }

    let title: String
    let make: @Sendable () async throws -> URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            SentTransferredFile(try await export.make())
        }
    }
}

/// Draws the PDFs, off the main thread. US Letter pages.
nonisolated enum Renderer {
    nonisolated struct Section: Sendable {
        var title: String
        var lines: [String]
        var images: [URL]
    }

    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    static let margin: CGFloat = 48

    static var folder: URL {
        let url = URL.temporaryDirectory.appending(path: "TroveExports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func output(_ name: String) -> URL {
        folder.appending(path: "\(name).pdf", directoryHint: .notDirectory)
    }

    /// A title and its images, one image per page, with an optional footer on every page.
    static func pages(title: String, images: [URL], footer: String?, fileName: String) -> URL? {
        let url = output(fileName)
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format(title: title))
        do {
            try renderer.writePDF(to: url) { context in
                for (index, imageURL) in images.enumerated() {
                    context.beginPage()
                    var y = margin
                    if index == 0 {
                        y = draw(title, font: .systemFont(ofSize: 20, weight: .semibold), at: y)
                        y += 12
                    }
                    if let image = UIImage(contentsOfFile: imageURL.path(percentEncoded: false)) {
                        let bottom = page.height - margin - (footer == nil ? 0 : 28)
                        drawImage(image, in: CGRect(x: margin, y: y, width: page.width - margin * 2, height: bottom - y))
                    }
                    if let footer { drawFooter(footer) }
                }
            }
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path(percentEncoded: false))
            return url
        } catch {
            return nil
        }
    }

    /// A cover with a title, then each section's lines and images.
    static func book(title: String, subtitle: String, sections: [Section], fileName: String) -> URL? {
        let url = output(fileName)
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format(title: title))
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                var y = draw(title, font: .systemFont(ofSize: 24, weight: .bold), at: margin)
                y = draw(subtitle, font: .systemFont(ofSize: 12), color: .darkGray, at: y + 6)
                y += 18
                for section in sections {
                    let needed: CGFloat = 40 + CGFloat(section.lines.count) * 16
                    if y + needed > page.height - margin {
                        context.beginPage()
                        y = margin
                    }
                    y = draw(section.title, font: .systemFont(ofSize: 15, weight: .semibold), at: y)
                    for line in section.lines {
                        if y > page.height - margin - 16 {
                            context.beginPage()
                            y = margin
                        }
                        y = draw(line, font: .systemFont(ofSize: 11), color: .darkGray, at: y + 2)
                    }
                    y += 14
                    for imageURL in section.images {
                        guard let image = UIImage(contentsOfFile: imageURL.path(percentEncoded: false)) else { continue }
                        context.beginPage()
                        drawImage(image, in: page.insetBy(dx: margin, dy: margin))
                        y = page.height
                    }
                }
            }
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path(percentEncoded: false))
            return url
        } catch {
            return nil
        }
    }

    private static func format(title: String) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Trove",
        ]
        return format
    }

    /// Draws wrapped text across the page and returns the y under it.
    @discardableResult
    private static func draw(_ text: String, font: UIFont, color: UIColor = .black, at y: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = page.width - margin * 2
        let bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        (text as NSString).draw(with: CGRect(x: margin, y: y, width: width, height: ceil(bounds.height)), options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        return y + ceil(bounds.height)
    }

    private static func drawFooter(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: UIColor.gray]
        (text as NSString).draw(in: CGRect(x: margin, y: page.height - margin + 6, width: page.width - margin * 2, height: 14), withAttributes: attributes)
    }

    private static func drawImage(_ image: UIImage, in frame: CGRect) {
        let size = image.size
        guard size.width > 0, size.height > 0, frame.width > 0, frame.height > 0 else { return }
        let scale = min(frame.width / size.width, frame.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        image.draw(in: CGRect(x: frame.midX - drawn.width / 2, y: frame.minY, width: drawn.width, height: drawn.height))
    }
}
