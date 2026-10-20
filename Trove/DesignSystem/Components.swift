import SwiftUI

// The pieces every Trove screen is built from, matching the Trove canvas: the blue header that
// fades into the gray background (the Hearth color header), white 22 pt cards, small tinted
// icon tiles, and the urgency chips.

/// The blue header that fades into the gray background. Fixed behind the scroll view. Every
/// Hearth app draws the same header in its own color.
struct HeaderGradient: View {
    /// How far down the screen the color reaches before it's gone, as a share of the screen's
    /// height: half on iPhone, 40% on iPad.
    var fraction: CGFloat?

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // On iPhone the color holds longer before it fades (eased), so it reads stronger in the
        // shorter space; on iPad, an even fade from the very top to the very bottom.
        let curve = sizeClass == .compact ? Self.phoneCurve : Self.evenCurve
        let start = Brand.skyDeep
        let end = Brand.skyMid
        GeometryReader { geo in
            LinearGradient(
                stops: curve.map { point in
                    Gradient.Stop(color: start.mix(with: end, by: point.location).opacity(point.opacity), location: point.location)
                },
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: geo.size.width, height: geo.size.height * (fraction ?? (sizeClass == .compact ? 0.5 : 0.4)))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// The color's strength at points down the gradient (0 = top, 1 = where it's gone).
    private static let phoneCurve: [(location: Double, opacity: Double)] = [
        (0, 1), (0.3, 0.88), (0.6, 0.5), (0.85, 0.15), (1, 0),
    ]
    private static let evenCurve: [(location: Double, opacity: Double)] = [(0, 1), (1, 0)]
}

/// A screen with the blue header: an optional small line above a big white title, an optional
/// line under it, then cards. Toolbar items come from the caller. On iPad the content keeps to a
/// readable column while the color runs edge to edge.
struct TroveScreen<Content: View>: View {
    /// The widest the cards get (iPad, Mac).
    static var readableWidth: CGFloat { 760 }

    @Environment(\.colorScheme) private var colorScheme
    var title: String
    var eyebrow: String?
    var subtitle: String?
    /// Large title in the content (tabs) or a small centered title in the bar (details).
    var largeTitle = true
    @ViewBuilder var content: () -> Content

    init(_ title: String, eyebrow: String? = nil, subtitle: String? = nil, largeTitle: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.largeTitle = largeTitle
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if largeTitle || eyebrow != nil || subtitle != nil {
                    VStack(alignment: .leading, spacing: 3) {
                        if let eyebrow {
                            Text(eyebrow.uppercased())
                                .font(.footnote.weight(.semibold))
                                .tracking(0.6)
                                .opacity(0.8)
                        }
                        if largeTitle {
                            Text(title)
                                .font(.largeTitle.bold())
                                .accessibilityAddTraits(.isHeader)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .opacity(0.85)
                        }
                    }
                    // A touch softer in Light Mode, where pure white over the lighter blue glares.
                    .foregroundStyle(.white.opacity(colorScheme == .light ? 0.92 : 1))
                    .padding(.horizontal, 4)
                }
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
            .frame(maxWidth: Self.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) { HeaderGradient() }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if largeTitle {
                // The title is drawn large in the content, as in the designs.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            } else {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A white card with the designs' 22 pt corners.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}

/// Rows inside a white card, with hairlines between them.
struct CardList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    var items: Data
    var inset: CGFloat = 16
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 {
                    Divider().padding(.leading, inset)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}

/// A quiet, uppercase label over a card ("DOCUMENTS"), with an optional control on the right.
struct CardLabel<Trailing: View>: View {
    var title: String
    var symbol: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.ink)
                    .accessibilityHidden(true)
            }
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 4)
    }
}

extension CardLabel where Trailing == EmptyView {
    init(_ title: String, symbol: String? = nil) {
        self.init(title: title, symbol: symbol, trailing: { EmptyView() })
    }
}

/// "Assets", "Needs attention": the bold section titles, with an optional control on the right.
struct SectionTitle<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title, trailing: { EmptyView() })
    }
}

/// A symbol on a soft rounded square: blue by default, or an urgency's colors.
struct IconTile: View {
    var symbol: String
    var size: CGFloat = 36
    var foreground: Color = Brand.ink
    var background: Color = Brand.tint
    var circle = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.28)))
            .accessibilityHidden(true)
    }
}

/// A small capsule: "5 mo", "Expired", "6 wk".
struct UrgencyChip: View {
    var text: String
    var urgency: Urgency

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(urgency.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(urgency.fill, in: .capsule)
    }
}

/// A small tinted capsule button, like Documents › Add.
struct TintedCapsuleButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.footnote.weight(.bold))
                }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(Brand.tint, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// The wide blue button at the bottom of a screen ("Scan a document").
struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Brand.sky)
    }
}

/// An empty state inside a card.
struct EmptyCard: View {
    var systemName: String
    var title: String
    var message: String

    var body: some View {
        Card {
            VStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.largeTitle)
                    .foregroundStyle(Brand.ink)
                    .accessibilityHidden(true)
                Text(title).font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

/// A row's chevron.
struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

/// A label and value inside a card, with a hairline under it unless it's the last.
struct FactRow<Value: View>: View {
    var label: String
    var isLast = false
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                value()
                    .multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
            .padding(.vertical, 12)
            if !isLast { Divider() }
        }
    }
}

extension FactRow where Value == Text {
    init(_ label: String, value: String, isLast: Bool = false) {
        self.init(label: label, isLast: isLast) { Text(value) }
    }
}
