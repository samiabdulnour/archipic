import SwiftUI

/// Fullscreen, black-background pinch-zoom viewer — the native counterpart of
/// the web "introspection" view. Pinch to zoom, drag to pan, double-tap to
/// toggle 1×/3×, single-tap (when not zoomed) to dismiss.
struct IntrospectionView: View {
    let image: UIImage?
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableImage(image: image, onSingleTapWhenUnzoomed: onClose)
                    .ignoresSafeArea()
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .statusBarHidden(true)
    }
}

/// UIScrollView-backed zoomable image: reliable pinch + pan + double-tap.
/// Layout happens in `layoutSubviews` (in the scroll-view subclass) so the
/// image always fills the screen correctly once the real bounds are known —
/// which `updateUIView` can miss.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    var onSingleTapWhenUnzoomed: () -> Void

    func makeUIView(context: Context) -> ZoomScrollView {
        ZoomScrollView(image: image, onSingleTap: onSingleTapWhenUnzoomed)
    }

    func updateUIView(_ uiView: ZoomScrollView, context: Context) {}
}

/// A self-contained zoomable scroll view: fits the image to the screen, pinch
/// to zoom (up to 6×), pan when zoomed, double-tap to toggle 3×, single tap
/// (when unzoomed) to dismiss.
final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private let onSingleTap: () -> Void

    init(image: UIImage, onSingleTap: @escaping () -> Void) {
        self.onSingleTap = onSingleTap
        super.init(frame: .zero)

        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        backgroundColor = .black
        contentInsetAdjustmentBehavior = .never

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // While unzoomed, keep the image filling the viewport (aspect-fit).
        if zoomScale == minimumZoomScale {
            imageView.frame = bounds
            contentSize = bounds.size
        }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    private func centerImage() {
        let w = bounds.width, h = bounds.height
        let cw = imageView.frame.width, ch = imageView.frame.height
        imageView.frame.origin = CGPoint(x: max(0, (w - cw) / 2),
                                         y: max(0, (h - ch) / 2))
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gr.location(in: imageView)
            let target = min(maximumZoomScale, 3)
            let rect = CGRect(x: point.x - (bounds.width / target) / 2,
                              y: point.y - (bounds.height / target) / 2,
                              width: bounds.width / target,
                              height: bounds.height / target)
            zoom(to: rect, animated: true)
        }
    }

    @objc private func handleSingleTap() {
        if zoomScale <= minimumZoomScale { onSingleTap() }
    }
}
