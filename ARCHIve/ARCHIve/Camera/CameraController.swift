import AVFoundation
import UIKit
import Observation
import CoreImage
import Metal

/// Aspect ratios offered in the camera, expressed as the *portrait* ratio
/// (width / height). Capture crops the full sensor frame to this.
/// Reference = photos found out in the world; Project = a site-specific shoot
/// where a project is chosen once and a sequence is shot into it.
enum CaptureMode { case reference, project }

enum CaptureAspect: String, CaseIterable, Identifiable {
    case fourThree = "4:3"      // the full sensor
    case square = "1:1"
    case sixteenNine = "16:9"

    var id: String { rawValue }

    /// width / height in portrait. The preview is letterboxed to this and the
    /// capture is cropped to the same ratio, so what you frame is what you get.
    var portraitRatio: CGFloat {
        switch self {
        case .square: return 1
        case .fourThree: return 3.0 / 4.0
        case .sixteenNine: return 9.0 / 16.0
        }
    }
}

/// Owns the AVCaptureSession. All session mutation happens on `sessionQueue`;
/// observable UI state is always written back on the main thread so SwiftUI
/// stays consistent. Public methods are intended to be called from the main
/// thread (SwiftUI), and they hop to the session queue internally.
@Observable
final class CameraController: NSObject {
    let session = AVCaptureSession()

    // Observable UI state (written on main).
    var authorized = false
    var permissionDenied = false
    var isRunning = false
    var flashMode: AVCaptureDevice.FlashMode = .off
    var aspect: CaptureAspect = .fourThree
    var gridOn = true
    var levelOn = true
    var timerSeconds = 0           // 0 | 3 | 10
    var zoomFactor: CGFloat = 1.0
    var maxZoom: CGFloat = 1.0
    /// Architectural keystone: when on, the live preview is warped (and the
    /// saved photo corrected) to keep verticals straight as the phone tilts.
    var keystoneOn = true   // always available; the slider amount (0 = none) governs it
    /// Manual keystone amount (−1…1), set by the slider. 0 = none.
    var keystoneStrength: Double = 0

    // Capture context (mirrors the web app's camera modes).
    var mode: CaptureMode = .reference
    var currentProject: String?            // the project shots land in (Project mode)
    var captureType: String = "building"   // Type segment: building | element | graphic
    var position: AVCaptureDevice.Position = .back

    /// Selected colour look (film-simulation style), applied live + on capture.
    var colorLook: CameraLook = .original

    /// Hidden preview layer used only to convert taps to device points for focus.
    @ObservationIgnored weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored weak var metalView: CameraMetalView?
    /// Latest raw preview frame (for rendering the look-picker thumbnails).
    @ObservationIgnored var latestFrame: CIImage?

    // Plain snapshots read on the video queue (avoid touching observable state off-main).
    @ObservationIgnored private var liveKeystone: Double = 0
    @ObservationIgnored private var liveLook: CameraLook = .original
    @ObservationIgnored private var pendingKeystone: Double?   // strength to correct at capture
    @ObservationIgnored private var pendingLook: CameraLook = .original

    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "archive.camera.video")
    @ObservationIgnored private var videoDevice: AVCaptureDevice?
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "archive.camera.session")
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var captureHandler: ((Data?) -> Void)?
    /// True from the moment a capture is requested until its completion fires.
    /// Set/read only on the main thread (capture() and deliver()), so a rapid
    /// second shutter tap can't overwrite the in-flight handler + pending* and
    /// silently drop the first photo.
    @ObservationIgnored private var captureInFlight = false
    /// Portrait crop ratio (width/height) the saved photo is cropped to. Set by
    /// the view from the live framing geometry so the save matches the preview.
    @ObservationIgnored private var pendingCropRatio: CGFloat = 3.0 / 4.0

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: Permission + setup

    func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
            configureIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.onMain {
                    guard let self else { return }
                    self.authorized = granted
                    self.permissionDenied = !granted
                    if granted { self.configureIfNeeded() }
                }
            }
        default:
            permissionDenied = true
        }
    }

    private func configureIfNeeded() {
        guard !configured else { start(); return }
        configured = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.videoDevice = device

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality
            }

            if let conn = self.photoOutput.connection(with: .video),
               conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }

            // Live frames for the Metal viewfinder.
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
            if let vc = self.videoOutput.connection(with: .video),
               vc.isVideoRotationAngleSupported(90) { vc.videoRotationAngle = 90 }

            self.session.commitConfiguration()

            let maxZ = min(device.activeFormat.videoMaxZoomFactor, 8.0)
            self.session.startRunning()
            self.onMain {
                self.maxZoom = maxZ
                self.isRunning = true
            }
        }
    }

    func start() {
        guard configured else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            self.onMain { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.onMain { self.isRunning = false }
        }
    }

    // MARK: Flip front/back

    func flipCamera() {
        let newPos: AVCaptureDevice.Position = (position == .back) ? .front : .back
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            for input in self.session.inputs {
                if let di = input as? AVCaptureDeviceInput, di.device.hasMediaType(.video) {
                    self.session.removeInput(di)
                }
            }
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPos),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoDevice = device
            }
            if let conn = self.photoOutput.connection(with: .video),
               conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
            if let vc = self.videoOutput.connection(with: .video) {
                if vc.isVideoRotationAngleSupported(90) { vc.videoRotationAngle = 90 }
                if vc.isVideoMirroringSupported { vc.isVideoMirrored = (newPos == .front) }
            }
            self.session.commitConfiguration()
            let maxZ = min(self.videoDevice?.activeFormat.videoMaxZoomFactor ?? 1, 8.0)
            self.onMain {
                self.position = newPos
                self.maxZoom = maxZ
                self.zoomFactor = 1
            }
        }
    }

    // MARK: Tap to focus + exposure

    /// `layerPoint` is a point in the preview layer's coordinate space.
    /// Call on the main thread (uses the preview layer).
    func focusAndExpose(atLayerPoint layerPoint: CGPoint) {
        guard let devicePoint = previewLayer?.captureDevicePointConverted(fromLayerPoint: layerPoint) else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = device.isFocusModeSupported(.autoFocus) ? .autoFocus : .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = device.isExposureModeSupported(.autoExpose) ? .autoExpose : .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    /// Manual exposure compensation in EV (e.g. dragging the sun up/down after a
    /// tap-to-focus), clamped to the device's supported range.
    func setExposureBias(_ ev: Float) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                let v = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, ev))
                device.setExposureTargetBias(v, completionHandler: nil)
                device.unlockForConfiguration()
            } catch { }
        }
    }

    // MARK: Zoom

    func setZoom(_ factor: CGFloat) {
        let clamped = max(1.0, min(factor, maxZoom))
        zoomFactor = clamped
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch { }
        }
    }

    // MARK: Capture

    // MARK: Keystone + colour look (processed live in the Metal pipeline)

    func attachMetal(_ view: CameraMetalView) {
        metalView = view
        previewLayer = view.focusLayer
        sessionQueue.async { [weak self, weak view] in
            guard let self else { return }
            DispatchQueue.main.async { view?.focusLayer.session = self.session }
        }
    }

    func setKeystoneEnabled(_ on: Bool) { keystoneOn = on; liveKeystone = on ? keystoneStrength : 0 }

    /// Manual keystone amount (−1…1); reflected live on the next frame.
    func setKeystoneStrength(_ v: Double) {
        keystoneStrength = max(-1, min(1, v))
        liveKeystone = keystoneOn ? keystoneStrength : 0
    }

    func setColorLook(_ look: CameraLook) { colorLook = look; liveLook = look }

    /// Redraw to `.up` orientation so Core Image works in display space.
    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = image.scale  // don't 3× the pixels
        let r = UIGraphicsImageRenderer(size: image.size, format: fmt)
        return r.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    // Metal-backed (GPU) — far more memory-efficient than the default software
    // context, part of avoiding the jetsam OOM on the heavy looks.
    @ObservationIgnored private let stillContext: CIContext = {
        if let dev = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: dev) }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    /// Apply the same keystone + colour look as the live preview to a still.
    private func processedStill(_ image: UIImage, keystone: Double, look: CameraLook) -> UIImage {
        let upright = CameraController.normalized(image)
        guard let cg = upright.cgImage else { return image }
        var ci = CIImage(cgImage: cg)
        // Cap processing resolution. Running grain/bloom on a full 24–48 MP frame
        // spikes memory and the OS jetsam-kills the app (signal 9) — and only on the
        // heavy looks, which is the reported symptom. 4096 px longest side (~12 MP)
        // is plenty for the journal/poster and renders safely.
        let longest = max(ci.extent.width, ci.extent.height)
        let maxDim: CGFloat = 4096
        if longest > maxDim {
            let f = maxDim / longest
            ci = ci.transformed(by: CGAffineTransform(scaleX: f, y: f))
        }
        let processed = CameraProcessing.apply(to: ci, keystone: keystone, look: look, grain: Settings.grainEnabled)
        guard let out = stillContext.createCGImage(processed, from: processed.extent) else { return upright }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }

    /// Call on the main thread. `completion` is delivered on the main thread.
    /// `cropRatio` (portrait width/height) is the exact region the preview is
    /// showing, so the saved photo matches the frame.
    func capture(cropRatio: CGFloat, completion: @escaping (Data?) -> Void) {
        guard configured else { completion(nil); return }
        // One capture at a time: ignore a second tap while one is outstanding,
        // rather than overwriting the handler and dropping the first frame.
        guard !captureInFlight else { completion(nil); return }
        captureInFlight = true
        captureHandler = completion
        let flash = self.flashMode
        let keystone: Double? = keystoneOn ? keystoneStrength : nil
        let look = self.colorLook

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.pendingKeystone = keystone
            self.pendingLook = look
            self.pendingCropRatio = cropRatio
            // No camera (e.g. the Simulator) → safe no-op instead of throwing.
            guard self.session.isRunning, self.photoOutput.connection(with: .video) != nil else {
                self.onMain { self.deliver(nil) }
                return
            }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            if self.photoOutput.supportedFlashModes.contains(flash) {
                settings.flashMode = flash
            }
            settings.photoQualityPrioritization = .quality
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func deliver(_ data: Data?) {
        let handler = captureHandler
        captureHandler = nil
        captureInFlight = false
        handler?(data)
    }

    /// Center-crop a UIImage to the given portrait ratio (width / height).
    static func crop(_ image: UIImage, toRatio ratio: CGFloat) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        // Match orientation: if the pixel buffer is landscape, invert ratio.
        let targetRatio = (w > h) ? (1.0 / ratio) : ratio
        var cw = w, ch = w / targetRatio
        if ch > h { ch = h; cw = h * targetRatio }
        cw = min(w, cw); ch = min(h, ch)
        let rect = CGRect(x: (w - cw) / 2, y: (h - ch) / 2, width: cw, height: ch).integral
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let ratio = pendingCropRatio   // set on session queue before capture; safe here
        guard error == nil, let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            onMain { self.deliver(nil) }
            return
        }
        let processed = processedStill(image, keystone: pendingKeystone ?? 0, look: pendingLook)
        let cropped = CameraController.crop(processed, toRatio: ratio)
        let jpeg = cropped.jpegData(compressionQuality: 0.9)
        onMain { self.deliver(jpeg) }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let raw = CIImage(cvPixelBuffer: pb)
        // Grain off for the live preview — it's baked into the captured photo only.
        let processed = CameraProcessing.apply(to: raw, keystone: liveKeystone, look: liveLook, grain: false)
        DispatchQueue.main.async { [weak self] in
            self?.metalView?.update(processed)
            self?.latestFrame = raw
        }
    }
}
