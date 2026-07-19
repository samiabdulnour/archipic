import SwiftUI
import CoreImage
import Metal

/// Native-Camera-style film-look picker: a horizontal strip of thumbnail swatches
/// — the live scene rendered through each look — that sits BELOW the shutter, so
/// the capture frame keeps its full size. Tap a swatch to select; the selected
/// one gets a white border. The caller shows the look's name above the shutter.
struct LooksStrip: View {
    @Bindable var camera: CameraController
    @State private var thumbs: [String: UIImage] = [:]

    // Metal-backed, matching the live camera path; caches off so repeated opens
    // don't creep memory.
    private static let ctx: CIContext = {
        if let d = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: d, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    private let swatch: CGFloat = 52

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CameraLook.allCases) { look in
                        swatchButton(look).id(look)
                    }
                }
                .padding(.horizontal, 6)
            }
            .onAppear { proxy.scrollTo(camera.colorLook, anchor: .center) }
        }
        .frame(height: swatch)
        .task { await render() }
    }

    private func swatchButton(_ look: CameraLook) -> some View {
        let on = camera.colorLook == look
        return Button {
            withAnimation(.snappy(duration: 0.2)) { camera.setColorLook(look) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                if let img = thumbs[look.rawValue] {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.white.opacity(0.10))
                }
            }
            .frame(width: swatch, height: swatch)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(on ? Color.white : Color.white.opacity(0.18), lineWidth: on ? 2.5 : 1))
        }
        .buttonStyle(.plain)
    }

    /// Render each look once from the current preview frame, progressively (a
    /// `Task.yield` between renders keeps the UI responsive). A nil frame — e.g.
    /// the Simulator, which has no camera — leaves neutral placeholder swatches.
    private func render() async {
        guard let base = camera.latestFrame else { return }
        let e = base.extent
        guard e.width > 0, e.height > 0 else { return }
        // Centre-square crop → small, so each look renders cheaply.
        let side = min(e.width, e.height)
        let crop = CGRect(x: e.midX - side / 2, y: e.midY - side / 2, width: side, height: side)
        let sq = base.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let f = 140 / side
        let small = sq.transformed(by: CGAffineTransform(scaleX: f, y: f))
        for look in CameraLook.allCases {
            // Render each swatch off the main actor: createCGImage forces a
            // synchronous GPU flush, and doing ~10 of them inline here (this method
            // mutates @State, so it runs on the MainActor) hitches the UI as the
            // strip opens. CIImage/CIContext are immutable and thread-safe.
            let img = await Task.detached { () -> UIImage? in
                let g = CameraProcessing.colored(small, look: look, applyGrain: false)
                guard let cg = Self.ctx.createCGImage(g, from: g.extent) else { return nil }
                return UIImage(cgImage: cg)
            }.value
            if let img { thumbs[look.rawValue] = img }
            await Task.yield()
        }
    }
}
