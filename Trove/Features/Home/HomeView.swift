import SwiftUI

/// Home: what needs a look first (expiring, expired, originals nobody can find), then the
/// assets, then what was added lately. From the Trove canvas.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @State private var store = TroveStore.shared
    @State private var household = HearthHouseholdStore.shared

    var body: some View {
        let attention = Attention.items(store: store)
        TroveScreen("Trove", subtitle: summary) {
            // The plan couldn't renew: update the payment method.
            HearthBillingBanner()

            if store.state.isEmpty {
                welcome
            } else {
                if !attention.isEmpty {
                    attentionCard(attention)
                } else {
                    allClear
                }
                assetsSection
                recentSection
            }
        }
        .refreshable { await store.syncNow() }
        .troveToolbar {
            Button("Add Document", systemImage: "plus") { router.add() }
        }
    }

    /// "48 documents across 6 assets and 4 people".
    private var summary: String {
        let documents = store.state.documents.count
        guard documents > 0 else { return "Your family’s important papers" }
        let people = Set(store.documents.compactMap(\.owner.personID)).count
        var parts = [documents == 1 ? "1 document" : "\(documents) documents"]
        var across: [String] = []
        if !store.state.assets.isEmpty { across.append(store.state.assets.count == 1 ? "1 asset" : "\(store.state.assets.count) assets") }
        if people > 0 { across.append(people == 1 ? "1 person" : "\(people) people") }
        if !across.isEmpty { parts.append("across " + across.formatted(.list(type: .and))) }
        return parts.joined(separator: " ")
    }

    // MARK: Needs attention

    private func attentionCard(_ items: [AttentionItem]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Needs attention")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if items.count > 3 {
                    NavigationLink(value: Destination.attention) {
                        Text("See all").font(.subheadline)
                    }
                    .foregroundStyle(Brand.ink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
            ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                AttentionRow(item: item)
                if index < min(items.count, 3) - 1 {
                    Divider().padding(.leading, 64)
                }
            }
            .padding(.bottom, 4)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private var allClear: some View {
        Card {
            HStack(spacing: 12) {
                IconTile(symbol: "checkmark.seal")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing needs attention").font(.headline)
                    Text("Nothing is expiring soon, and every original has a place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Assets

    private var assetsSection: some View {
        VStack(spacing: 12) {
            SectionTitle(title: "Assets") {
                Button("Add") { router.tab = .assets }
                    .font(.subheadline)
                    .foregroundStyle(Brand.ink)
            }
            if store.assets.isEmpty {
                Button { router.tab = .assets } label: {
                    Card {
                        HStack(spacing: 12) {
                            IconTile(symbol: "plus", circle: true)
                            Text("Add a home or a vehicle to keep its title, insurance and warranties together.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(store.assets) { asset in
                        NavigationLink(value: Destination.asset(asset.id)) {
                            AssetTile(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Recent

    private var recentSection: some View {
        let recent = store.state.documents.values.sorted { $0.createdAt > $1.createdAt }.prefix(4)
        return VStack(spacing: 12) {
            SectionTitle("Recently added")
            CardList(items: Array(recent)) { document in
                NavigationLink(value: Destination.document(document.id)) {
                    DocumentRow(document: document, showsOwner: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: First run

    private var welcome: some View {
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Start with what you’d need in a hurry")
                        .font(.headline)
                    ForEach(Self.firstDocuments, id: \.self) { type in
                        Button {
                            router.add(AddDocumentRequest(type: type, scanFirst: true))
                        } label: {
                            HStack(spacing: 12) {
                                IconTile(symbol: type.symbol, size: 34)
                                Text(type.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "doc.viewfinder")
                                    .foregroundStyle(Brand.ink)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Scans a \(type.label.localizedLowercase)")
                    }
                }
            }
            PrimaryButton(title: "Scan a Document", systemImage: "doc.viewfinder") {
                router.add(AddDocumentRequest(scanFirst: true))
            }
            Text("Scans are read on this \(DeviceName.current) and kept in your iCloud, encrypted. Nothing goes to Hearth’s servers.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private static let firstDocuments: [DocumentType] = [.passport, .driversLicense, .birthCertificate, .socialSecurityCard, .insuranceCard]
}

/// One row of Needs attention: opens the document or the place.
struct AttentionRow: View {
    var item: AttentionItem
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let id = item.documentID {
                NavigationLink(value: Destination.document(id)) { content }
            } else if let id = item.placeID {
                NavigationLink(value: Destination.place(id)) { content }
            } else {
                Button { router.tab = .originals } label: { content }
            }
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        HStack(spacing: 12) {
            IconTile(
                symbol: item.symbol,
                foreground: item.urgency == .calm ? Color(.secondaryLabel) : item.urgency.ink,
                background: item.urgency.fill
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let chip = item.chip {
                UrgencyChip(text: chip, urgency: item.urgency)
            } else {
                Chevron()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Home › Needs attention › See all.
struct AttentionListView: View {
    @State private var store = TroveStore.shared

    var body: some View {
        let items = Attention.items(store: store)
        TroveScreen("Needs Attention", largeTitle: false) {
            if items.isEmpty {
                EmptyCard(systemName: "checkmark.seal", title: "All caught up", message: "Nothing is expiring soon, and every original has a place.")
            } else {
                CardList(items: items, inset: 64) { item in
                    AttentionRow(item: item)
                }
            }
        }
        .refreshable { await store.syncNow() }
        .troveToolbar()
    }
}
