import SwiftUI

/// One asset: what it is, its facts (the VIN masked until Face ID), and every document filed
/// under it, with the documents it usually has suggested. From the Trove canvas.
struct AssetDetailView: View {
    let assetID: String
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var store = TroveStore.shared
    @State private var editing = false

    var body: some View {
        if let asset = store.asset(assetID) {
            content(asset)
        } else {
            ContentUnavailableView("This asset was removed", systemImage: "square.grid.2x2")
                .troveToolbar()
        }
    }

    private func content(_ asset: TroveAsset) -> some View {
        let documents = store.documents(for: .asset(asset.id))
        let missing = asset.kind.usualDocuments.filter { type in !documents.contains { $0.type == type } }
        let facts = asset.kind.factKeys.compactMap { key in asset.fact(key).map { AssetFact(key: key, value: $0) } }
        return TroveScreen(asset.name, eyebrow: asset.kind.label, subtitle: sharingLine(documents.count)) {
            hero(asset)

            if !facts.isEmpty {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                            FactRow(label: fact.key.label, isLast: index == facts.count - 1) {
                                if fact.key.isSensitive {
                                    SecureValue(value: fact.value, reason: "Show the \(fact.key.label)")
                                } else {
                                    Text(fact.value)
                                        .font(fact.key.usesMonospace ? .subheadline.monospaced() : .subheadline)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            CardLabel("Documents")
            if documents.isEmpty {
                EmptyCard(systemName: asset.kind.symbol, title: "No documents yet", message: "Scan its \(asset.kind.usualDocuments.prefix(2).map { $0.label.localizedLowercase }.formatted(.list(type: .or))) to start.")
            } else {
                CardList(items: documents, inset: 62) { document in
                    NavigationLink(value: Destination.document(document.id)) {
                        DocumentRow(document: document)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !missing.isEmpty {
                CardLabel("Usually kept with a \(asset.kind.label.localizedLowercase)")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(missing.enumerated()), id: \.element) { index, type in
                            Button {
                                router.add(AddDocumentRequest(owner: .asset(asset.id), type: type))
                            } label: {
                                HStack(spacing: 12) {
                                    IconTile(symbol: type.symbol, size: 32, foreground: Color(.secondaryLabel), background: Color(.tertiarySystemFill))
                                    Text(type.label).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Scan").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            if index < missing.count - 1 { Divider().padding(.leading, 60) }
                        }
                    }
                }
            }

            if !asset.notes.isEmpty {
                CardLabel("Notes")
                Card { Text(asset.notes).font(.subheadline) }
            }

            PrimaryButton(title: "Scan a Document", systemImage: "doc.viewfinder") {
                router.add(AddDocumentRequest(owner: .asset(asset.id)))
            }
        }
        .refreshable { await store.syncNow() }
        .troveToolbar {
            Button("Edit", systemImage: "pencil") { editing = true }
            Menu("More", systemImage: "ellipsis") {
                Button("Add Document", menuIcon: "plus") {
                    router.add(AddDocumentRequest(owner: .asset(asset.id)))
                }
                Button("Edit Details", menuIcon: "pencil") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            AssetEditor(asset: asset) { dismiss() }
        }
    }

    /// The asset's kind as a big soft symbol over the header.
    private func hero(_ asset: TroveAsset) -> some View {
        HStack {
            Spacer()
            Image(systemName: asset.kind.symbol)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 8)
                .padding(.vertical, 8)
                .accessibilityHidden(true)
            Spacer()
        }
    }

    private func sharingLine(_ count: Int) -> String {
        let documents = count == 1 ? "1 document" : "\(count) documents"
        return TroveSharing.isShared ? "Shared with Household · \(documents)" : documents
    }
}
