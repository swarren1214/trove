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
                // Where the pages come from: a big Scan card, with Photos and Files beside each
                // other below it. Nothing opens until the person picks one.
                SourceChoices(
                    canScan: DocumentCamera.isSupported,
                    photoItems: $photoItems,
                    scan: { showsCamera = true },
                    files: { showsFiles = true }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
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

/// The ways to add pages. Scanning is how most documents arrive, so it's the big card; Photos
/// and Files sit side by side below it (stacked at the largest text sizes).
private struct SourceChoices: View {
    var canScan: Bool
    @Binding var photoItems: [PhotosPickerItem]
    var scan: () -> Void
    var files: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 12) {
            if canScan {
                Button(action: scan) { ScanCard() }
                    .buttonStyle(SourcePressStyle())
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                    SourceTile(symbol: "photo.on.rectangle.angled", title: "Photos", detail: "Pictures you’ve already taken")
                }
                .buttonStyle(SourcePressStyle())
                Button(action: files) {
                    SourceTile(symbol: "folder.fill", title: "Files", detail: "PDFs and images")
                }
                .buttonStyle(SourcePressStyle())
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Scan with Camera: a deep blue card with a page in a viewfinder.
private struct ScanCard: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Scan with Camera")
                    .font(.title3.bold())
                Text("Trove finds the edges and straightens every page.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The picture goes when there's no room for it (narrow screens, big text).
            ViewThatFits(in: .horizontal) {
                ScanIllustration()
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background {
            // The header's deep end into ink, so white text reads (4.9:1 at the darker end).
            LinearGradient(colors: [Brand.skyDeep, Color(hex: 0x0F7A9C)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.10))
                        .frame(width: 180, height: 180)
                        .offset(x: 60, y: -80)
                }
        }
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .contentShape(.rect(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A card tilted in a camera viewfinder.
private struct ScanIllustration: View {
    var body: some View {
        ZStack {
            ViewfinderCorners(length: 16)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 84, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Brand.sky.opacity(0.75))
                        .frame(width: 14, height: 17)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().frame(width: 22, height: 4)
                        Capsule().frame(width: 15, height: 4)
                    }
                    .foregroundStyle(Brand.sky.opacity(0.55))
                }
                Capsule().frame(width: 38, height: 4)
                Capsule().frame(width: 28, height: 4)
                Capsule().frame(width: 34, height: 4)
            }
            .foregroundStyle(Color(hex: 0x0F7A9C).opacity(0.28))
            .padding(9)
            .frame(width: 58, height: 70, alignment: .topLeading)
            .background(.white, in: .rect(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            .rotationEffect(.degrees(-7))
        }
        .frame(width: 88, height: 100)
        .accessibilityHidden(true)
    }
}

/// The four corners of a camera viewfinder.
private struct ViewfinderCorners: Shape {
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 6
        // Top left.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        // Top right.
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        // Bottom right.
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        // Bottom left.
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

/// Photos or Files: a white glyph on a blue tile, a title and a quiet line, on a card.
private struct SourceTile: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Brand.sky, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24, style: .continuous))
        .contentShape(.rect(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A soft press: the card dips a little.
private struct SourcePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
