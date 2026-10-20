import SwiftUI

/// Assets: the family's homes, vehicles and other valuables, each holding its documents.
struct AssetsView: View {
    @State private var store = TroveStore.shared
    @State private var purchases = HearthPurchases.shared
    @State private var adding = false
    @State private var showsPaywall = false

    private var canAdd: Bool {
        purchases.isUnlocked || store.state.assets.count < AppConfig.freeAssetLimit
    }

    var body: some View {
        TroveScreen("Assets", subtitle: subtitle) {
            if store.assets.isEmpty {
                EmptyCard(
                    systemName: "square.grid.2x2",
                    title: "No assets yet",
                    message: "Add a home, a vehicle or anything valuable to keep its title, insurance, warranties and receipts together."
                )
                PrimaryButton(title: "Add an Asset", systemImage: "plus") { adding = true }
            } else {
                ForEach(AssetKind.allCases) { kind in
                    let group = store.assets.filter { $0.kind == kind }
                    if !group.isEmpty {
                        SectionTitle(kind.pluralLabel)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(group) { asset in
                                NavigationLink(value: Destination.asset(asset.id)) {
                                    AssetTile(asset: asset)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !canAdd {
                    HearthLockedCard(feature: TrovePlus.assets)
                }
            }
        }
        .refreshable { await store.syncNow() }
        .troveToolbar {
            Button("Add Asset", systemImage: "plus") {
                if canAdd { adding = true } else { showsPaywall = true }
            }
        }
        .sheet(isPresented: $adding) {
            AssetEditor(asset: nil)
        }
        .hearthPaywall(isPresented: $showsPaywall, feature: TrovePlus.assets, startWith: .app)
    }

    private var subtitle: String {
        let count = store.state.assets.count
        guard count > 0 else { return "Homes, vehicles and valuables" }
        let documents = store.documents.filter { $0.owner.assetID != nil }.count
        return "\(count == 1 ? "1 asset" : "\(count) assets") · \(documents == 1 ? "1 document" : "\(documents) documents")"
    }
}

/// An asset on Home and Assets: its kind's icon, its name, and how many documents, with what
/// needs attention.
struct AssetTile: View {
    var asset: TroveAsset
    @State private var store = TroveStore.shared

    var body: some View {
        let documents = store.documents(for: .asset(asset.id))
        let urgent = documents.compactMap { Attention.expiryLine($0) }.filter { $0.urgency != .calm }
        VStack(alignment: .leading, spacing: 14) {
            IconTile(symbol: asset.kind.symbol, size: 34, circle: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail(documents: documents.count, urgent: urgent.count))
                    .font(.footnote)
                    .foregroundStyle(urgent.isEmpty ? Color(.secondaryLabel) : (urgent.map { $0.urgency }.max() ?? .soon).ink)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func detail(documents: Int, urgent: Int) -> String {
        let count = documents == 1 ? "1 doc" : "\(documents) docs"
        return urgent == 0 ? count : "\(count) · \(urgent) due soon"
    }
}
