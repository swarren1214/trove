import SwiftUI
import UIKit

/// The moment after a scan, while Trove reads it on the device.
///
/// 1. Reading: the page floats in the middle with a jade glow running around its edge (Apple
///    Intelligence's edge light, in Trove's color), a soft beam sweeps down the page, and each
///    line of text Vision finds lights up where it is on the page.
/// 2. Found: the glow settles, the page eases up, and what Trove read drops in underneath as
///    chips, one after another (the kind of document, whose it is, when it expires, the end of
///    its number), with a checkmark and a tap of the Taptic Engine. Then it hands back to the
///    form, already filled in.
/// 3. Nothing found: a quiet note to fill it in by hand.
///
/// Reduce Motion keeps the glow still, drops the beam, and fades instead of moving.
struct ReadingView: View {
    enum Phase: Equatable {
        case reading
        case found([FoundField])
        case nothing
    }

    struct FoundField: Identifiable, Equatable {
        var id: String { symbol + text }
        var symbol: String
        var text: String
    }

    var page: UIImage
    /// Where Vision found lines of text, as fractions of the page (top-left origin).
    var boxes: [CGRect]
    var phase: Phase
    /// Tap to skip ahead once it's found something.
    var onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var shownBoxes = 0
    @State private var shownFields = 0
    @State private var checked = false

    private var isReading: Bool { phase == .reading }

    private var fields: [FoundField] {
        if case .found(let fields) = phase { return fields }
        return []
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            pageCard
                .scaleEffect(isReading ? 1 : 0.86)
                .offset(y: isReading || reduceMotion ? 0 : -12)
            VStack(spacing: 14) {
                caption
                if !fields.isEmpty {
                    chips
                }
            }
            .frame(minHeight: 150, alignment: .top)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .contentShape(.rect)
        .onTapGesture { if !isReading { onSkip() } }
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: phase)
        .task(id: boxes.count) { await revealBoxes() }
        .task(id: fields) { await revealFields() }
        .sensoryFeedback(.success, trigger: checked) { _, new in new }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: The page

    private var pageCard: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let aspect = page.size.height > 0 ? page.size.width / page.size.height : 0.7
        return Image(uiImage: page)
            .resizable()
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { textHighlights }
            .overlay { if isReading && !reduceMotion { beam } }
            .clipShape(shape)
            .frame(maxWidth: 320, maxHeight: 360)
            .background { glow(shape).blur(radius: 18).opacity(0.9) }
            .overlay { glow(shape).opacity(isReading ? 1 : 0.55) }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
            .accessibilityHidden(true)
    }

    /// The edge light: a jade-to-mint gradient that runs around the page while reading, and
    /// holds still once it's done.
    private func glow(_ shape: RoundedRectangle) -> some View {
        TimelineView(.animation(paused: !isReading || reduceMotion)) { context in
            let turn = reduceMotion ? 0 : context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 3) / 3
            shape
                .strokeBorder(
                    AngularGradient(
                        colors: [Brand.jade, Color(hex: 0x7FE3C9), .white, Color(hex: 0x2E8C7C), Color(hex: 0xA6F0DC), Brand.jade],
                        center: .center,
                        angle: .degrees(turn * 360)
                    ),
                    lineWidth: isReading ? 3 : 2
                )
        }
    }

    /// A soft band of light moving down the page, over and over.
    private var beam: some View {
        TimelineView(.animation) { context in
            let progress = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 1.8) / 1.8
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Color(hex: 0x7FE3C9).opacity(0.55), .white.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geo.size.height * 0.28)
                .offset(y: (geo.size.height * 1.28) * progress - geo.size.height * 0.28)
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
    }

    /// Each line Vision found, lit up in place, top to bottom. They fade once it's done.
    private var textHighlights: some View {
        GeometryReader { geo in
            ForEach(Array(boxes.prefix(shownBoxes).enumerated()), id: \.offset) { _, box in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hex: 0x7FE3C9).opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color(hex: 0x2E8C7C).opacity(0.55), lineWidth: 1))
                    .frame(width: box.width * geo.size.width + 4, height: box.height * geo.size.height + 3)
                    .position(x: box.midX * geo.size.width, y: box.midY * geo.size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .opacity(isReading ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: isReading)
        .allowsHitTesting(false)
    }

    // MARK: Below the page

    private var caption: some View {
        HStack(spacing: 8) {
            switch phase {
            case .reading:
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                Text("Reading on this \(DeviceName.current)…")
            case .found:
                Image(systemName: "checkmark.circle.fill")
                    .symbolEffect(.bounce, value: checked)
                    .foregroundStyle(Brand.ink)
                Text("Here’s what Trove found")
            case .nothing:
                Image(systemName: "text.viewfinder")
                Text("Couldn’t read this one. Fill it in below.")
            }
        }
        .font(.headline)
        .foregroundStyle(phase == .nothing ? Color.secondary : Color.primary)
        .contentTransition(.opacity)
        .id(phaseKey)
        .transition(.opacity.combined(with: .offset(y: 6)))
    }

    private var chips: some View {
        HearthFlowLayout(spacing: 8) {
            ForEach(Array(fields.prefix(shownFields))) { field in
                Label(field.text, systemImage: field.symbol)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(Brand.jade.opacity(0.18)), in: .capsule)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.6).combined(with: .opacity).combined(with: .offset(y: -18)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: 340)
    }

    private var phaseKey: String {
        switch phase {
        case .reading: "reading"
        case .found: "found"
        case .nothing: "nothing"
        }
    }

    private var accessibilityText: String {
        switch phase {
        case .reading: "Reading the document"
        case .found(let fields): "Found " + fields.map(\.text).formatted(.list(type: .and))
        case .nothing: "Couldn’t read this document. Fill in the details by hand."
        }
    }

    // MARK: Timing

    /// Lights the lines up one after another, a little faster when there are many.
    private func revealBoxes() async {
        let step = boxes.count > 24 ? 0.025 : 0.05
        while shownBoxes < boxes.count, isReading {
            try? await Task.sleep(for: .seconds(step))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { shownBoxes += 1 }
        }
    }

    private func revealFields() async {
        guard !fields.isEmpty else { return }
        try? await Task.sleep(for: .seconds(0.25))
        for _ in fields {
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) { shownFields += 1 }
            try? await Task.sleep(for: .seconds(0.12))
        }
        checked = true
    }
}

extension ReadingView.FoundField {
    /// What to show for a reading: up to four things, never the whole number.
    static func fields(from reading: DocumentReading, ownerName: String?) -> [ReadingView.FoundField] {
        var fields: [ReadingView.FoundField] = []
        if let type = reading.type { fields.append(.init(symbol: type.symbol, text: type.label)) }
        if let name = ownerName ?? (reading.name.isEmpty ? nil : reading.name) {
            fields.append(.init(symbol: "person.fill", text: name))
        }
        if let expires = reading.expiresOn.flatMap({ HearthDay.date(from: $0) }) {
            fields.append(.init(symbol: "calendar", text: "Expires \(expires.formatted(.dateTime.month(.abbreviated).year()))"))
        }
        if !reading.number.isEmpty {
            fields.append(.init(symbol: "number", text: "•••• " + SecureValue.tail(reading.number)))
        } else if !reading.vin.isEmpty {
            fields.append(.init(symbol: "car.side", text: "VIN •••• " + SecureValue.tail(reading.vin)))
        }
        return fields
    }
}

#Preview("Reading, then found") {
    ReadingPreview()
}

/// A stand-in page with lines of "text", reading for a few seconds and then finding a passport.
private struct ReadingPreview: View {
    @State private var phase: ReadingView.Phase = .reading

    private static let lines: [CGRect] = (0..<9).map { index in
        CGRect(x: 0.1, y: 0.12 + Double(index) * 0.085, width: index % 3 == 0 ? 0.55 : 0.78, height: 0.04)
    }

    private static let page: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 420)).image { context in
        UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 420))
        UIColor(red: 0.72, green: 0.76, blue: 0.82, alpha: 1).setFill()
        for line in lines {
            context.fill(CGRect(x: line.minX * 600, y: line.minY * 420, width: line.width * 600, height: line.height * 420))
        }
    }

    var body: some View {
        ReadingView(page: Self.page, boxes: Self.lines, phase: phase) { phase = .reading }
            .task(id: phase) {
                guard phase == .reading else { return }
                try? await Task.sleep(for: .seconds(2.5))
                phase = .found([
                    .init(symbol: DocumentType.passport.symbol, text: "Passport"),
                    .init(symbol: "person.fill", text: "Ava"),
                    .init(symbol: "calendar", text: "Expires Mar 2027"),
                    .init(symbol: "number", text: "•••• 0218"),
                ])
            }
    }
}
