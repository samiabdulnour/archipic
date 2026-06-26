import UIKit
import CoreImage
import Metal

/// Applies a photo's non-destructive edits (rotation → crop → tilt → colour look)
/// to a source image. A no-op when the photo has no edits, so untouched photos
/// pay nothing. The original pixels are never modified.
enum PhotoEdits {
    private static let ctx: CIContext = {
        if let dev = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: dev) }
        return CIContext()
    }()

    static func render(_ base: UIImage, _ photo: Photo) -> UIImage {
        guard photo.hasEdits else { return base }
        let up = normalizedUp(base)
        guard let cg = up.cgImage else { return base }
        var ci = CIImage(cgImage: cg)

        // 1) Rotation (clockwise on screen → negative angle in CI's y-up space).
        if photo.editRotation % 360 != 0 {
            let rad = -CGFloat(photo.editRotation) * .pi / 180
            ci = ci.transformed(by: CGAffineTransform(rotationAngle: rad))
            ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
        }

        // 2) Crop — normalised rect with a top-left origin; CI is y-up so flip Y.
        let e = ci.extent
        if photo.cropX > 0.0001 || photo.cropY > 0.0001 || photo.cropW < 0.9999 || photo.cropH < 0.9999 {
            let cw = CGFloat(photo.cropW) * e.width
            let ch = CGFloat(photo.cropH) * e.height
            let cx = e.minX + CGFloat(photo.cropX) * e.width
            let cy = e.minY + (e.height - CGFloat(photo.cropY) * e.height - ch)
            ci = ci.cropped(to: CGRect(x: cx, y: cy, width: cw, height: ch))
            ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
        }

        // 3) Tilt + colour look — the same engine as the live camera.
        let look = CameraLook(rawValue: photo.editLookRaw ?? "") ?? .original
        ci = CameraProcessing.apply(to: ci, keystone: photo.editKeystone, look: look, grain: Settings.grainEnabled)

        guard let outCG = ctx.createCGImage(ci, from: ci.extent) else { return up }
        return UIImage(cgImage: outCG)
    }

    /// Redraw to `.up` so pixel-space crop/rotate behave predictably.
    private static func normalizedUp(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = image.scale  // don't 3× the pixels
        let r = UIGraphicsImageRenderer(size: image.size, format: fmt)
        return r.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }
}
