import SwiftUI

/// Adding or editing an asset: what kind, its name, and the facts that kind has.
struct AssetEditor: View {
    var asset: TroveAsset?
    /// Called after the asset is deleted, so the screen showing it can close.
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TroveAsset
    @State private var facts: [AssetFact.Key: String]
    @State private var confirmsDelete = false
    @State private var store = TroveStore.shared

    init(asset: TroveAsset?, onDelete: (() -> Void)? = nil) {
        self.asset = asset
        self.onDelete = onDelete
        let start = asset ?? TroveAsset(kind: .vehicle, name: "")
        _draft = State(initialValue: start)
        _facts = State(initialValue: Dictionary(start.facts.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a }))
    }

    private var isValid: Bool { !resolvedName.isEmpty }

    /// The name, or one made from the vehicle's year, make and model.
    private var resolvedName: String {
        let typed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        if draft.kind == .vehicle {
            return [facts[.year], facts[.model] ?? facts[.make]].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(AssetKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    TextField(namePrompt, text: $draft.name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    ForEach(draft.kind.factKeys, id: \.self) { key in
                        TextField(key.label, text: binding(key))
                            .keyboardType(key == .year ? .numberPad : .default)
                            .textInputAutocapitalization(key == .vin || key == .plate || key == .serial ? .characters : .words)
                            .autocorrectionDisabled(key.usesMonospace)
                            .font(key.usesMonospace ? .body.monospaced() : .body)
                    }
                } footer: {
                    if draft.kind.factKeys.contains(where: \.isSensitive) {
                        Text("The \(draft.kind.factKeys.filter(\.isSensitive).map(\.label).formatted(.list(type: .and))) stays hidden until someone unlocks it with Face ID.")
                    }
                }

                Section("Notes") {
                    TextField("Anything worth knowing", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if asset != nil {
                    Section {
                        Button("Delete Asset", role: .destructive) { confirmsDelete = true }
                    } footer: {
                        Text("Its documents and their scans are deleted too.")
                    }
                }
            }
            .navigationTitle(asset == nil ? "New Asset" : "Edit Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton(asset == nil ? "Add" : "Save") { save() }
                        .disabled(!isValid)
                }
            }
            .alert("Delete \(draft.name)?", isPresented: $confirmsDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    store.deleteAsset(draft.id)
                    dismiss()
                    onDelete?()
                }
            } message: {
                let count = store.documents(for: .asset(draft.id)).count
                Text(count == 0
                     ? "This removes it from your devices and your iCloud\(TroveSharing.isShared ? ", and from everyone you share with" : "")."
                     : "This removes it and its \(count == 1 ? "document" : "\(count) documents") from your devices and your iCloud\(TroveSharing.isShared ? ", and from everyone you share with" : ""). It can’t be undone.")
            }
        }
    }

    private var namePrompt: String {
        switch draft.kind {
        case .vehicle: "Name (like 2021 Highlander)"
        case .home: "Name (like Maple St. house)"
        case .other: "Name (like Engagement ring)"
        }
    }

    private func binding(_ key: AssetFact.Key) -> Binding<String> {
        Binding(get: { facts[key] ?? "" }, set: { facts[key] = $0 })
    }

    private func save() {
        var saved = draft
        saved.name = resolvedName
        saved.facts = []
        for key in saved.kind.factKeys {
            saved.setFact(key, facts[key] ?? "")
        }
        store.save(saved)
        dismiss()
    }
}
