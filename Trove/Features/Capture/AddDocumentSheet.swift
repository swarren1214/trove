import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Adding a document, from the Trove canvas: scan it (or pick photos or a PDF), Trove reads the
/// type, name, number and dates on the device, the person checks them, says whose it is and
/// where the original is kept, and saves. Every page is kept exactly as captured.
struct AddDocumentSheet: View {
    var request: AddDocumentRequest

    @Environment(\.dismiss) private var dismiss
    @State private var store = TroveStore.shared
    @State private var household = HearthHouseholdStore.shared
    @State private var draft: DocumentDraft
    @State private var pages: [CapturedPage] = []
    @State private var showsCamera = false
    @State private var showsFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var reading = false
    @State private var readNote: String?
    /// The reading animation over the sheet: the first page, where its text is, and how far along.
    @State private var readingPage: UIImage?
    @State private var readingBoxes: [CGRect] = []
    @State private var readingPhase: ReadingView.Phase = .reading
    @State private var finishReading: (() -> Void)?
    @State private var problem: String?
    @State private var confirmsDiscard = false

    init(request: AddDocumentRequest) {
        self.request = request
        if let id = request.documentID, let existing = TroveStore.shared.document(id) {
            _draft = State(initialValue: DocumentDraft(existing))
        } else {
            let type = request.type ?? .other
            var draft = DocumentDraft(type: type, owner: request.owner ?? .household)
            if request.owner == nil, type.usuallyBelongsToPerson, let me = HearthHouseholdStore.shared.me {
                draft.owner = .person(me.id)
            }
            _draft = State(initialValue: draft)
        }
    }

    private var isRescan: Bool { request.documentID != nil }

    var body: some View {
        NavigationStack {
            Form {
                captureSection
                if !pages.isEmpty || !isRescan {
                    DocumentFormSections(draft: $draft)
                }
                if !isRescan {
                    Section {
                        Label("Scans and numbers stay on your devices and in your family’s iCloud, encrypted. Nothing goes to Hearth’s servers.", systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isRescan ? "Rescan" : "New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton {
                        if pages.isEmpty { dismiss() } else { confirmsDiscard = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton(isRescan ? "Save" : "Add") { save() }
                        .disabled(reading || (isRescan && pages.isEmpty))
                }
            }
            .interactiveDismissDisabled(!pages.isEmpty)

            .fullScreenCover(isPresented: $showsCamera) {
                DocumentCamera { images in
                    showsCamera = false
                    add(images, source: "Camera")
                } onCancel: {
                    showsCamera = false
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importFiles(urls) }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    photoItems = []
                    add(images, source: "Photos")
                }
            }
            .alert("Discard This Document?", isPresented: $confirmsDiscard) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("The pages you scanned aren’t saved yet.")
            }
            .alert("Couldn’t Add That", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .task {
                if request.scanFirst, DocumentCamera.isSupported { showsCamera = true }
            }
        }
        // Over the whole sheet, its bar included, while Trove reads the pages.
        .overlay {
            if let readingPage {
                ReadingView(page: readingPage, boxes: readingBoxes, phase: readingPhase) {
                    finishReading?()
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
    }

    // MARK: Capture

    @ViewBuilder
    private var captureSection: some View {
        Section {
            if pages.isEmpty {
                // Where the pages come from, as rows in the list, like Settings: a colored icon,
                // what it does, and a line on how.
                if DocumentCamera.isSupported {
                    Button { showsCamera = true } label: {
                        SourceRow(symbol: "doc.viewfinder", title: "Scan with Camera", detail: "Finds the edges and straightens each page")
                    }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                    SourceRow(symbol: "photo.on.rectangle", title: "Choose from Photos", detail: "Pictures you’ve already taken")
                }
                Button { showsFiles = true } label: {
                    SourceRow(symbol: "folder", title: "Import from Files", detail: "PDFs and images")
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(pages) { page in
                            VStack(spacing: 4) {
                                Image(uiImage: page.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 60)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        Button("Remove \(page.label)", systemImage: "xmark.circle.fill") {
                                            withAnimation { remove(page) }
                                        }
                                        .labelStyle(.iconOnly)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .buttonStyle(.plain)
                                        .padding(3)
                                    }
                                Text(page.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Menu {
                            sourceMenu
                        } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 84, height: 60)
                                    .overlay { Image(systemName: "plus").foregroundStyle(Brand.ink) }
                                Text("Add page").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Add a page")
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                if reading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading on this \(DeviceName.current)…").foregroundStyle(.secondary)
                    }
                } else if let readNote {
                    Label(readNote, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Brand.ink)
                }
            }
        } header: {
            Text(pages.isEmpty ? "Add pages" : "Pages")
        } footer: {
            if pages.isEmpty {
                Text(isRescan ? "The new pages replace the ones in Trove now." : "Add the front and the back. Trove reads them on this \(DeviceName.current) and keeps every photo exactly as it is.")
            }
        }
    }

    @ViewBuilder
    private var sourceMenu: some View {
        if DocumentCamera.isSupported {
            Button("Scan", menuIcon: "camera") { showsCamera = true }
        }
        PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
            Label { Text("Photos") } icon: { Image.menuIcon("photo.on.rectangle") }
        }
        Button("Files", menuIcon: "folder") { showsFiles = true }
    }

    private func add(_ images: [UIImage], source: String) {
        guard !images.isEmpty else { return }
        let start = pages.count
        for (offset, image) in images.enumerated() {
            pages.append(CapturedPage(image: image, source: source, label: CapturedPage.label(for: start + offset)))
        }
        read()
    }

    private func remove(_ page: CapturedPage) {
        pages.removeAll { $0.id == page.id }
        for index in pages.indices { pages[index].label = CapturedPage.label(for: index) }
    }

    /// Images and PDFs from Files: each PDF page becomes a page.
    private func importFiles(_ urls: [URL]) {
        var images: [UIImage] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            if let document = PDFDocument(data: data) {
                for index in 0..<min(document.pageCount, 12) {
                    guard let page = document.page(at: index) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    let scale = min(3, 2_000 / max(bounds.width, bounds.height, 1))
                    images.append(page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox))
                }
            } else if let image = UIImage(data: data) {
                images.append(image)
            }
        }
        if images.isEmpty {
            problem = "Trove couldn’t open those files. Try a PDF or a photo."
        } else {
            add(images, source: "Files")
        }
    }

    /// Reads the pages and fills in what it finds, never over what the person typed. The
    /// reading animation plays over the sheet meanwhile (`ReadingView`): at least long enough to
    /// see, then what was found, then the form, filled in.
    private func read() {
        guard !pages.isEmpty else { return }
        reading = true
        readNote = nil
        let images = pages.map(\.image)
        let typeWasChosen = request.type != nil || isRescan
        let expecting = typeWasChosen ? draft.type : nil
        let first = images[0]
        readingBoxes = []
        readingPhase = .reading
        withAnimation(.easeOut(duration: 0.3)) { readingPage = first }
        // Where the text is, only for the animation; quick and rough.
        Task {
            let orientation = VisionReading.orientation(of: first)
            let boxes = await Task.detached(priority: .userInitiated) { () -> [CGRect] in
                guard let image = first.cgImage else { return [] }
                return VisionReading.textBoxes(in: image, orientation: orientation)
            }.value
            readingBoxes = boxes
        }
        Task {
            let started = Date.now
            let result = await DocumentReader.read(images, expecting: expecting)
            // Long enough to see it read, even when a barcode answers at once.
            let elapsed = Date.now.timeIntervalSince(started)
            if elapsed < 1.6 { try? await Task.sleep(for: .seconds(1.6 - elapsed)) }

            if result.isEmpty {
                readingPhase = .nothing
                try? await Task.sleep(for: .seconds(1.3))
                closeReading()
                readNote = DocumentReader.modelIsAvailable ? nil : "Fill in the details below."
                return
            }
            var filled = draft
            filled.take(result, household: household, store: store, typeWasChosen: typeWasChosen)
            let owner = household.member(filled.owner.personID)?.firstName
            readingPhase = .found(ReadingView.FoundField.fields(from: result, ownerName: owner))
            let note: String = switch result.source {
            case .barcode: "Read from the barcode. Check the details below."
            case .machineReadableZone: "Read from the passport’s code. Check the details below."
            case .text, .none: "Read on this \(DeviceName.current). Check the details below."
            }
            var finished = false
            let finish = {
                guard !finished else { return }
                finished = true
                closeReading()
                withAnimation { draft.take(result, household: household, store: store, typeWasChosen: typeWasChosen) }
                readNote = note
            }
            finishReading = finish
            try? await Task.sleep(for: .seconds(2.2))
            finish()
        }
    }

    private func closeReading() {
        reading = false
        finishReading = nil
        withAnimation(.easeInOut(duration: 0.35)) { readingPage = nil }
    }

    // MARK: Saving

    private func save() {
        let newScans: [(scan: TroveScan, data: Data)] = pages.compactMap { page in
            guard let jpeg = TroveFiles.jpeg(from: page.image) else { return nil }
            let scan = TroveScan(label: page.label, source: page.source, width: jpeg.width, height: jpeg.height)
            return (scan, jpeg.data)
        }
        if let id = request.documentID, var existing = store.document(id) {
            existing = draft.applied(to: existing)
            // The new pages replace the old ones.
            existing.scans = []
            store.save(existing, newScans: newScans)
        } else {
            let document = draft.applied(to: TroveDocument(type: draft.type))
            store.save(document, newScans: newScans)
        }
        if draft.expires != nil, UserDefaults.standard.bool(forKey: SettingsKey.expiryReminders) {
            Task { await Reminders.requestPermission() }
        }
        dismiss()
    }
}

/// A page captured in the Add sheet, before it's saved.
struct CapturedPage: Identifiable {
    let id = UUID()
    let image: UIImage
    let source: String
    var label: String
    let thumbnail: UIImage

    init(image: UIImage, source: String, label: String) {
        self.image = image
        self.source = source
        self.label = label
        thumbnail = image.preparingThumbnail(of: ScanImages.fit(image.size, side: 240)) ?? image
    }

    static func label(for index: Int) -> String {
        switch index {
        case 0: "Front"
        case 1: "Back"
        default: "Page \(index + 1)"
        }
    }
}

/// One way to add pages: a blue icon square, a title and a quiet line, like a Settings row.
private struct SourceRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Brand.sky, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Chevron()
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}
