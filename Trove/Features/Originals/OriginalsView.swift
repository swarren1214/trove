import SwiftUI

/// Originals: where the paper copies actually are. The places, the originals nobody has found
/// yet, and the emergency packet. From the Trove canvas.
struct OriginalsView: View {
    @State private var store = TroveStore.shared
    @State private var purchases = HearthPurchases.shared
    @State private var addingPlace = false
    @State private var placing: TroveDocument?
    @State private var showsPaywall = false

    var body: some View {
        let missing = store.documentsWithoutOriginal
        TroveScreen("Originals", subtitle: "Where the paper copies actually are") {
            if store.places.isEmpty {
                EmptyCard(
                    systemName: "mappin.and.ellipse",
                    title: "Where do you keep them?",
                    message: "Add the fire safe, the safe deposit box, the filing cabinet, or the attorney who holds your will."
                )
                PrimaryButton(title: "Add a Place", systemImage: "plus") { addingPlace = true }
            } else {
                CardList(items: store.places, inset: 68) { place in
                    NavigationLink(value: Destination.place(place.id)) {
                        PlaceRow(place: place, count: store.documents(inPlace: place.id).count)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Location unknown").font(.headline)
                        Spacer()
                        Text("\(missing.count)").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Urgency.soon.ink)
                    HearthFlowLayout(spacing: 8) {
                        ForEach(missing) { document in
                            Button { placing = document } label: {
                                Text(Attention.title(of: document))
                                    .font(.subheadline)
                                    .foregroundStyle(Urgency.soon.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Urgency.soon.fill, in: .capsule)
                                    .overlay(Capsule().strokeBorder(Urgency.soon.ink.opacity(0.18)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Choose where it’s kept")
                        }
                    }
                    Text("Found one? Tap it and pick where it lives.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            }

            emergencyPacket
        }
        .refreshable { await store.syncNow() }
        .troveToolbar {
            Button("Add Place", systemImage: "plus") { addingPlace = true }
        }
        .sheet(isPresented: $addingPlace) { PlaceEditor(place: nil) }
        .sheet(item: $placing) { document in PlacePicker(document: document) }
        .hearthPaywall(isPresented: $showsPaywall, feature: TrovePlus.emergencyPacket, startWith: .app)
    }

    /// A list of what the family has and where each original is, with no scans and no numbers,
    /// to give someone you trust. Made fresh each time it's shared, so it's never out of date.
    @ViewBuilder
    private var emergencyPacket: some View {
        if purchases.isUnlocked {
            ShareLink(item: TroveExport.emergencyPacket(store: store), preview: SharePreview("Emergency packet")) {
                emergencyPacketLabel
            }
            .buttonStyle(.plain)
            .disabled(store.documents.isEmpty)
        } else {
            Button { showsPaywall = true } label: { emergencyPacketLabel }
                .buttonStyle(.plain)
        }
    }

    private var emergencyPacketLabel: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "cross.case", size: 40, foreground: .white, background: Brand.sky, circle: true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Emergency packet").font(.headline).foregroundStyle(.primary)
                    if !purchases.isUnlocked {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("What your family has and where each original is, to give someone you trust. No scans, no numbers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Chevron()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .contentShape(.rect(cornerRadius: 22))
    }
}

/// A place in a list: its kind's icon, name, detail and how many originals, and when it was
/// last checked.
struct PlaceRow: View {
    var place: TrovePlace
    var count: Int

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: place.kind.symbol, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name).font(.headline).foregroundStyle(.primary)
                Text([place.detail, count == 1 ? "1 item" : "\(count) items"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(place.confirmedAt.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "Unchecked")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
