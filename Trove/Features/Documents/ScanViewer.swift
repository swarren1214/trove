import SwiftUI
import UIKit

/// A document's original scans, full size: swipe between pages, pinch to zoom.
struct ScanViewer: View {
    var document: TroveDocument
    var start: TroveScan
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String

    init(document: TroveDocument, start: TroveScan) {
        self.document = document
        self.start = start
        _selection = State(initialValue: start.id)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(document.scans) { scan in
                    ZoomableScan(scan: scan)
                        .tag(scan.id)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: document.scans.count > 1 ? .automatic : .never))
            .background(Color.black)
            .navigationTitle(document.scans.first { $0.id == selection }?.label ?? "Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .tint(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// One page, zoomable with a pinch or a double tap (UIScrollView does this best).
struct ZoomableScan: UIViewRepresentable {
    var scan: TroveScan

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .black
        let imageView = UIImageView(image: TroveFiles.scanImage(scan))
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = scan.label
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 3, height: scroll.bounds.height / 3)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// Present: the document full screen at full brightness, for handing the phone across a
/// counter. Swipe between pages; tap Done to put the brightness back.
struct PresentView: View {
    var document: TroveDocument
    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView {
                ForEach(document.scans) { scan in
                    ZoomableScan(scan: scan)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: document.scans.count > 1 ? .always : .never))
            Button("Done") { dismiss() }
                .buttonStyle(.glass)
                .padding()
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .onAppear {
            let screen = Self.screen
            previousBrightness = screen?.brightness
            screen?.brightness = 1
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            if let previousBrightness { Self.screen?.brightness = previousBrightness }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }?.screen
    }
}
