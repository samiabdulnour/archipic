import MetalKit
import CoreImage
import AVFoundation
import SwiftUI

/// Metal-backed live viewfinder: it renders processed `CIImage` frames (keystone
/// + colour look) so the preview matches the saved photo exactly. A hidden
/// AVCaptureVideoPreviewLayer rides along solely for tap→device-point focus.
final class CameraMetalView: MTKView {
    private let ciContext: CIContext
    private let queue: MTLCommandQueue
    private var image: CIImage?
    let focusLayer = AVCaptureVideoPreviewLayer()

    init() {
        // The live viewfinder is an MTKView and fundamentally needs a Metal device
        // and command queue; if either is genuinely unavailable the camera can't
        // render at all. Guard with a clear message instead of the old bogus
        // `?? MTLCreateSystemDefaultDevice()!` double-call / `makeCommandQueue()!`.
        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is required for the camera viewfinder but is unavailable on this device")
        }
        guard let q = dev.makeCommandQueue() else {
            fatalError("Could not create a Metal command queue for the camera viewfinder")
        }
        ciContext = CIContext(mtlDevice: dev)
        queue = q
        super.init(frame: .zero, device: dev)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        isOpaque = true
        focusLayer.videoGravity = .resizeAspectFill
        focusLayer.opacity = 0            // not shown; used only for focus mapping
        layer.addSublayer(focusLayer)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        focusLayer.frame = bounds
    }

    /// Push a new processed frame (call on the main thread).
    func update(_ ci: CIImage) {
        image = ci
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let image, let drawable = currentDrawable,
              let cb = queue.makeCommandBuffer() else { return }
        let size = drawableSize
        let e = image.extent
        guard e.width > 0, e.height > 0, size.width > 0 else { return }
        // Aspect-fill the frame into the drawable.
        let scale = max(size.width / e.width, size.height / e.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let se = scaled.extent
        let tx = (size.width - se.width) / 2 - se.minX
        let ty = (size.height - se.height) / 2 - se.minY
        let centered = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))
        let dest = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: cb)
        dest.isFlipped = true
        _ = try? ciContext.startTask(toRender: centered, from: CGRect(origin: .zero, size: size),
                                     to: dest, at: .zero)
        cb.present(drawable)
        cb.commit()
    }
}

struct MetalCameraPreview: UIViewRepresentable {
    let controller: CameraController
    func makeUIView(context: Context) -> CameraMetalView {
        let v = CameraMetalView()
        controller.attachMetal(v)
        return v
    }
    func updateUIView(_ uiView: CameraMetalView, context: Context) {}
}
