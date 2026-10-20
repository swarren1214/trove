import SwiftUI

/// Editing a document: its details, its pages (rename, reorder, remove), and deleting it.
struct DocumentEditor: View {
    var document: TroveDocument
    /// Called after the document is deleted, so the screen showing it can close.
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var store = TroveStore.shared
    @State private var draft: DocumentDraft
    @State private var scans: [TroveScan]
    @State private var confirmsDelete = false

    init(document: TroveDocument, onDelete: (() -> Void)? = nil) {
        self.document = document
        self.onDelete = onDelete
        _draft = State(initialValue: DocumentDraft(document))
        _scans = State(initialValue: document.scans)
    }

    var body: some View {
        NavigationStack {
            Form {
                DocumentFormSections(draft: $draft)

                if !scans.isEmpty {
                    Section {
                        ForEach($scans) { $scan in
                            HStack(spacing: 12) {
                                ScanThumbnail(scan: scan, symbol: document.type.symbol, width: 44, height: 34)
                                TextField("Page name", text: $scan.label)
                            }
                        }
                        .onDelete { scans.remove(atOffsets: $0) }
                        .onMove { scans.move(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        Text("Pages")
                    } footer: {
                        Text("Swipe to remove a page. Removed pages are deleted from your devices and iCloud when you save.")
                    }
                }

                Section {
                    Button("Delete Document", role: .destructive) { confirmsDelete = true }
                }
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCancelButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton("Save") { save() }
                }
            }
            .alert("Delete \(Attention.title(of: document))?", isPresented: $confirmsDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    store.deleteDocument(document.id)
                    dismiss()
                    onDelete?()
                }
            } message: {
                Text("Its scans are deleted from your devices and your iCloud\(TroveSharing.isShared ? ", and from everyone you share with" : ""). The paper original isn’t affected. It can’t be undone.")
            }
        }
    }

    private func save() {
        // Start from what's saved now, in case iCloud changed it while this was open.
        var updated = draft.applied(to: store.document(document.id) ?? document)
        updated.scans = scans.map { scan in
            var scan = scan
            scan.label = scan.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Page" : scan.label
            return scan
        }
        store.save(updated)
        dismiss()
    }
}
