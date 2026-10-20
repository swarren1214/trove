import SwiftUI
import UIKit

/// A document in a list: its type's icon (or its first scan), its title, what's known about it,
/// and how soon it expires.
struct DocumentRow: View {
    var document: TroveDocument
    /// Show whose it is under the title (lists that mix owners).
    var showsOwner = false
    @State private var store = TroveStore.shared

    var body: some View {
        HStack(spacing: 12) {
            ScanThumbnail(scan: document.scans.first, symbol: document.type.symbol, width: 34, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(showsOwner ? Attention.title(of: document) : document.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(subtitleUrgency.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let line = Attention.expiryLine(document), line.urgency != .calm, let expiry = document.expiryDate {
                let days = Attention.daysUntil(expiry)
                UrgencyChip(text: days < 0 ? "Expired" : Attention.chip(days: days), urgency: line.urgency)
            } else {
                Chevron()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var subtitleUrgency: Urgency {
        if document.originalIsMissing && Attention.expiryLine(document) == nil { return .soon }
        return .calm
    }

    private var subtitle: String {
        var parts: [String] = []
        if let line = Attention.expiryLine(document) { parts.append(line.text) }
        if let place = store.place(document.placeID) {
            parts.append(place.name)
        } else if document.originalIsMissing {
            parts.append("Where’s the original?")
        }
        if parts.isEmpty {
            parts.append(document.scans.isEmpty ? "No scan yet" : (document.scans.count == 1 ? "1 page" : "\(document.scans.count) pages"))
        }
        return parts.joined(separator: " · ")
    }
}

/// A scan's thumbnail, or the type's symbol on a soft tile when there's no scan yet.
struct ScanThumbnail: View {
    var scan: TroveScan?
    var symbol: String
    var width: CGFloat
    var height: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if scan != nil {
                Color(.tertiarySystemFill)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: min(width, height) * 0.45, weight: .semibold))
                    .foregroundStyle(Brand.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.tint)
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.separator), lineWidth: 0.5))
        .accessibilityHidden(true)
        .task(id: scan?.id) { image = await ScanImages.thumbnail(scan, side: max(width, height) * 3) }
    }
}

/// Small images of scans, made off the main thread and kept in memory.
@MainActor
enum ScanImages {
    private static let cache = NSCache<NSString, UIImage>()

    static func thumbnail(_ scan: TroveScan?, side: CGFloat) async -> UIImage? {
        guard let scan else { return nil }
        let key = "\(scan.id)-\(Int(side))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let url = TroveFiles.scanURL(scan)
        let image: UIImage? = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let full = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
            return full.preparingThumbnail(of: ScanImages.fit(full.size, side: side))
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    nonisolated static func fit(_ size: CGSize, side: CGFloat) -> CGSize {
        let scale = min(1, side / max(size.width, size.height, 1))
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}

/// A sensitive value (a document number, a VIN): masked to its last few characters until Face
/// ID, then shown for 30 seconds, or until Trove leaves the screen.
struct SecureValue: View {
    var value: String
    var reason: String
    var monospaced = true
    @State private var revealed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 8) {
            if revealed {
                Text(value)
                    .font(monospaced ? .subheadline.monospaced() : .subheadline)
                    .textSelection(.enabled)
                    .transition(.opacity)
                Button("Hide", systemImage: "eye.slash") { withAnimation { revealed = false } }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Brand.ink)
            } else {
                Text(Self.masked(value))
                    .font(monospaced ? .subheadline.monospaced() : .subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hidden, ends in \(Self.tail(value))")
                Button {
                    Task {
                        if await AppLock.confirm(reason) {
                            withAnimation { revealed = true }
                        }
                    }
                } label: {
                    Label("Show", systemImage: "faceid")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Brand.ink)
                }
                .accessibilityLabel("Show with Face ID")
            }
        }
        .buttonStyle(.plain)
        .task(id: revealed) {
            guard revealed else { return }
            try? await Task.sleep(for: .seconds(30))
            withAnimation { revealed = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { revealed = false }
        }
        .onDisappear { revealed = false }
    }

    static func tail(_ value: String) -> String {
        let clean = value.filter { !$0.isWhitespace }
        return String(clean.suffix(clean.count > 6 ? 4 : 2))
    }

    /// "•••••• 4821".
    static func masked(_ value: String) -> String {
        "••••••  " + tail(value)
    }
}

/// The big card at the top of a document: its type and title, who it belongs to, and its dates,
/// over the first scan (blurred) or the jade.
struct DocumentHeroCard: View {
    var document: TroveDocument
    var ownerName: String
    @State private var image: UIImage?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScanThumbnail(scan: document.scans.first, symbol: document.type.symbol, width: 86, height: 108)
            VStack(alignment: .leading, spacing: 8) {
                Text(document.type.label.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.72))
                Text(ownerName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        heroFact("Issued", document.issuedDate?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "—")
                        heroFact("Expires", document.expiryDate?.formatted(.dateTime.month(.abbreviated).day().year()) ?? (document.type.expires ? "—" : "Never"))
                    }
                    GridRow {
                        heroFact("Pages", document.scans.isEmpty ? "None yet" : "\(document.scans.count) scanned")
                        heroFact("Issuer", document.issuer.isEmpty ? "—" : document.issuer)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x24324F), Color(hex: 0x1A2440)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 24)
                        .opacity(0.35)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 10)
        .task(id: document.scans.first?.id) { image = await ScanImages.thumbnail(document.scans.first, side: 300) }
        .accessibilityElement(children: .combine)
    }

    private func heroFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
