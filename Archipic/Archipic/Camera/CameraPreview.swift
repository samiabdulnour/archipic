import SwiftUI
import AVFoundation

/// Hosts the AVCaptureVideoPreviewLayer. Tap-to-focus is handled by a SwiftUI
/// spatial-tap gesture in CameraView (a UIKit recognizer here gets swallowed by
/// the surrounding SwiftUI magnify gesture).
struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = controller.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        controller.previewLayer = view.videoPreviewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    /// A UIView whose backing layer is the preview layer (auto-resizes).
    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
