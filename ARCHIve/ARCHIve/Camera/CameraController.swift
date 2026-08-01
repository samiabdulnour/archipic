import AVFoundation
import UIKit
import Observation
import CoreImage
import Metal

/// Aspect ratios offered in the camera, expressed as the *portrait* ratio
/// (width / height). Capture crops the full sensor frame to this.

/// What the shutter captures: a still or a movie. The camera is one unified
/// interface; a project is attached optionally (top-left pill) regardless.
enum CaptureMediaMode { case photo, video }

/// Pure lens/zoom-stop math — no AVFoundation — so the multi-lens behaviour is
/// verifiable for every iPhone layout without a device (see the offline test
/// harness). `applyZoomModel` maps the real device into `model(...)`.
enum CameraZoom {
    enum Lens: Equatable { case ultraWide, wide, telephoto, other }
    struct Stop: Equatable { let factor: CGFloat; let label: String }

    /// Given a (virtual) device's `virtualDeviceSwitchOverVideoZoomFactors` and
    /// its constituent lenses (widest first), return the videoZoomFactor that
    /// frames the wide at "1×" and the display stops (0.5× / 1× / 2× / tele).
    /// - The widest lens sits at videoZoomFactor 1.0; each next lens starts at its
    ///   switch-over factor. "1×" is the wide's factor (2.0 when an ultra-wide is
    ///   the widest, 1.0 otherwise). Display× = factor / base.
    /// - Adds an Apple-style 2× (48-MP wide crop) when there's no native ~2× lens.
    static func model(switchovers: [CGFloat], lenses: [Lens],
                      is48MP: Bool, maxAvailable: CGFloat) -> (base: CGFloat, stops: [Stop]) {
        let native: [CGFloat] = [1.0] + switchovers
        let wideIndex = lenses.firstIndex(of: .wide)
        let base = wideIndex.flatMap { $0 < native.count ? native[$0] : nil } ?? 1.0
        let maxF = min(maxAvailable, base * 15)
        var stops: [Stop] = []
        if lenses.isEmpty {
            stops.append(Stop(factor: base, label: "1"))
        } else {
            for (i, _) in lenses.enumerated() where i < native.count {
                stops.append(Stop(factor: native[i], label: label(native[i] / base)))
            }
        }
        let has2 = stops.contains { abs($0.factor / base - 2) < 0.12 }
        if !has2 && is48MP && maxF >= base * 2 {
            stops.append(Stop(factor: base * 2, label: "2"))
        }
        return (base, stops.sorted { $0.factor < $1.factor })
    }

    /// Clean stop label for a display multiplier ("0.5", "1", "2", "5").
    static func label(_ mult: CGFloat) -> String {
        if mult < 0.95 { return "0.5" }
        let r = (mult * 2).rounded() / 2                 // snap to nearest 0.5
        return r.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", r) : String(format: "%.1f", r)
    }
}

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
    var zoomFactor: CGFloat = 1.0          // raw videoZoomFactor
    var maxZoom: CGFloat = 1.0             // raw max videoZoomFactor (kept for callers)
    /// videoZoomFactor that frames the wide camera at "1×" (2.0 on phones whose
    /// widest lens is the ultra-wide, 1.0 otherwise).
    var baseZoomFactor: CGFloat = 1.0
    var minZoomFactor: CGFloat = 1.0
    var maxZoomFactor: CGFloat = 1.0
    /// Architectural keystone: when on, the live preview is warped (and the
    /// saved photo corrected) to keep verticals straight as the phone tilts.
    var keystoneOn = true   // always available; the slider amount (0 = none) governs it
    /// Manual keystone amount (−1…1), set by the slider. 0 = none.
    var keystoneStrength: Double = 0

    // Capture context.
    var mediaMode: CaptureMediaMode = .photo
    var currentProject: String?            // optional project shots are filed into (nil = unfiled)
    var isRecording = false                // true while a movie is being recorded
    var videoCapable = false               // set once the session is up; gates the VIDEO toggle
    var position: AVCaptureDevice.Position = .back

    /// One lens/zoom stop for the switcher (e.g. 0.5× / 1× / 2× / 5×).
    struct ZoomStop: Identifiable, Equatable {
        let factor: CGFloat        // the videoZoomFactor this stop selects
        let label: String          // "0.5", "1", "2", "3", "5"
        var id: CGFloat { factor }
    }
    /// Lens/zoom stops for the switcher, widest first. Fewer than two → a
    /// single-lens phone, and the switcher stays hidden.
    var zoomStops: [ZoomStop] = []

    /// Current zoom as a display multiplier (1× = the wide camera).
    var displayZoom: CGFloat { baseZoomFactor > 0 ? zoomFactor / baseZoomFactor : zoomFactor }
    /// Live "×" readout, e.g. "1", "1.8", "0.5".
    var displayZoomLabel: String {
        let x = displayZoom
        if x < 0.95 { return String(format: "%.1f", x) }
        let r = (x * 10).rounded() / 10
        return r.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", r) : String(format: "%.1f", r)
    }
    /// The active stop's factor (largest stop ≤ current zoom) — drives which
    /// switcher button is highlighted.
    var activeStopFactor: CGFloat {
        zoomStops.last(where: { $0.factor <= zoomFactor + 0.05 })?.factor
            ?? zoomStops.first?.factor ?? baseZoomFactor
    }

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
    /// Grade the live preview? Off in video mode so what you see (ungraded)
    /// matches the straight movie that gets recorded.
    @ObservationIgnored private var liveGrade = true
    @ObservationIgnored private var pendingKeystone: Double?   // strength to correct at capture
    @ObservationIgnored private var pendingLook: CameraLook = .original

    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let movieOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "archive.camera.video")
    @ObservationIgnored private var videoDevice: AVCaptureDevice?
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "archive.camera.session")
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var movieAdded = false            // movie output attached to the session
    @ObservationIgnored private var movieUnderPhoto = false       // movie shares the .photo preset → switch needs no reconfig
    @ObservationIgnored private var audioAdded = false            // mic input added lazily on first record
    // Across a flip the incoming camera briefly delivers frames that don't match
    // its settled geometry (front settles to landscape, back to portrait), which
    // flashed a wrongly-oriented frame. Hold the viewfinder on its last good frame
    // until the geometry matches — so the flip is only as slow as the camera really
    // is, not a fixed guess. The deadline is just a safety net.
    @ObservationIgnored private var liveFront = false               // position, safe to read off-main
    @ObservationIgnored private var awaitingSettledFrame = false
    @ObservationIgnored private var settleDeadline: CFAbsoluteTime = 0
    @ObservationIgnored private var recordHandler: ((URL?) -> Void)?
    /// Main-thread debounce: true from the instant a start is requested until the
    /// recording finishes. `isRecording` only flips asynchronously on the session
    /// queue, so without this a quick double-tap starts a second recording that
    /// cancels the first (losing the clip). Read and written on the main thread.
    @ObservationIgnored private var recordPending = false
    @ObservationIgnored private var captureHandler: ((Data?) -> Void)?
    /// True from the moment a capture is requested until its completion fires.
    /// Set/read only on the main thread (capture() and deliver()), so a rapid
    /// second shutter tap can't overwrite the in-flight handler + pending* and
    /// silently drop the first photo.
    @ObservationIgnored private var captureInFlight = false
    /// Portrait crop ratio (width/height) the saved photo is cropped to. Set by
    /// the view from the live framing geometry so the save matches the preview.
    @ObservationIgnored private var pendingCropRatio: CGFloat = 3.0 / 4.0
    @ObservationIgnored private var pendingFront = false   // was this capture on the front camera?

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Lock every video connection to portrait, and mirror it for the front camera.
    ///
    /// Must be called **after** `commitConfiguration()`: swapping the device input
    /// rebuilds the connections, so anything set before the commit is discarded —
    /// which left the front camera sideways (a connection defaults to 0°).
    /// `isVideoMirrored` also requires the automatic adjustment to be off first.
    /// Call on the session queue.
    private func applyConnectionGeometry(front: Bool) {
        let named: [(String, AVCaptureConnection?)] = [
            ("photo",   photoOutput.connection(with: .video)),
            ("preview", videoOutput.connection(with: .video)),
            ("movie",   movieOutput.connection(with: .video)),
        ]
        for (name, conn) in named {
            guard let conn else { continue }
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            guard conn.isVideoMirroringSupported else { continue }
            conn.automaticallyAdjustsVideoMirroring = false
            // The viewfinder mirrors the front camera itself (see the delegate), so
            // pin this connection to "never mirror". It must be applied *inside* the
            // configuration block: applied after the commit it takes about a second
            // to land, and until it does the connection is still mirroring — so the
            // pipeline mirrors an already-mirrored frame, which after the rotation
            // reads as upside down. That was the flash on every flip.
            //
            // Stills and movies are oriented by the connection instead (they carry it
            // as EXIF / a track transform) and come out right; a late setting doesn't
            // matter for them, since nothing is shown live.
            // preview: never mirror here — the pipeline mirrors it (see delegate).
            // photo: never mirror — selfies save unmirrored like the native
            //   default, and this connection can't be trusted to apply settings
            //   predictably anyway (it claims rotations it doesn't perform).
            // movie: mirror front recordings (matches the mirrored viewfinder).
            switch name {
            case "preview", "photo": conn.isVideoMirrored = false
            default: conn.isVideoMirrored = front
            }
        }
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
                let device = self.bestBackDevice(),
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

            // Live frames for the Metal viewfinder.
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }

            // Attach the movie output up front when the `.photo` preset allows it,
            // so switching photo↔video needs no session change at all. Some devices
            // refuse it under `.photo`; there it's attached lazily on first video.
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
                self.movieAdded = true
                self.movieUnderPhoto = true   // recording coexists with .photo → no swap on switch
            }

            self.session.commitConfiguration()
            self.applyConnectionGeometry(front: false)
            self.liveFront = false
            self.session.startRunning()
            self.applyZoomModel(for: device)   // lens stops + open at 1×
            self.onMain {
                self.isRunning = true
                self.videoCapable = true
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
            let newDevice = newPos == .back
                ? self.bestBackDevice()
                : AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            if let device = newDevice,
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoDevice = device
            }
            // Set the geometry INSIDE the block so it commits atomically with the new
            // input — there's then no window in which the connection is still
            // mirroring (which flashed an upside-down frame).
            self.applyConnectionGeometry(front: newPos == .front)
            self.session.commitConfiguration()
            // Re-assert afterwards too: the commit can rebuild the connections, and
            // a connection that came back with defaults would be sideways.
            self.applyConnectionGeometry(front: newPos == .front)
            // Hold the viewfinder until this camera's frames match its settled
            // geometry, so the flip is as fast as the camera and never flashes.
            self.liveFront = (newPos == .front)
            self.awaitingSettledFrame = true
            self.settleDeadline = CFAbsoluteTimeGetCurrent() + 1.5
            self.onMain { self.position = newPos }
            if let device = self.videoDevice { self.applyZoomModel(for: device) }
        }
    }

    // MARK: Zoom model (multi-lens)

    /// The best back device for seamless multi-lens zoom: a virtual multi-camera
    /// (which auto-switches physical lenses by zoom factor — like the native
    /// Camera) when available, else the plain wide. Falls through gracefully on
    /// every model: triple → dual-wide → dual → wide.
    private func bestBackDevice() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] =
            [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        for t in types {
            if let d = AVCaptureDevice.default(t, for: .video, position: .back) { return d }
        }
        return AVCaptureDevice.default(for: .video)
    }

    /// Derive the lens/zoom stops from a device — the videoZoomFactor for each
    /// optical lens (0.5× / 1× / tele) plus an Apple-style 48-MP-crop 2× — set the
    /// "1×" base and the clamps, and open framed at 1× (the wide, not the
    /// ultra-wide). Call on the session queue after configuring the input.
    private func applyZoomModel(for device: AVCaptureDevice) {
        let switchovers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let lenses: [CameraZoom.Lens] = device.constituentDevices.map {
            switch $0.deviceType {
            case .builtInUltraWideCamera: return .ultraWide
            case .builtInWideAngleCamera: return .wide
            case .builtInTelephotoCamera: return .telephoto
            default:                      return .other
            }
        }
        // 48-MP wide → offer the Apple-style 2× crop. Scan the wide's formats (not
        // just the active one, which may be 12-MP-binned).
        let wideDevice = device.constituentDevices.first { $0.deviceType == .builtInWideAngleCamera }
            ?? (device.constituentDevices.isEmpty ? device : nil)
        let is48MP = (wideDevice?.formats ?? []).contains { fmt in
            fmt.supportedMaxPhotoDimensions.contains { Int($0.width) >= 7500 }
        }
        let minF = device.minAvailableVideoZoomFactor
        let maxAvail = device.maxAvailableVideoZoomFactor
        let (base, specs) = CameraZoom.model(switchovers: switchovers, lenses: lenses,
                                             is48MP: is48MP, maxAvailable: maxAvail)
        let maxF = min(maxAvail, base * 15)
        let stops = specs.map { ZoomStop(factor: $0.factor, label: $0.label) }

        // Open at 1× (the wide), not the ultra-wide's native 1.0.
        do { try device.lockForConfiguration(); device.videoZoomFactor = base; device.unlockForConfiguration() } catch {}

        let published = stops.count > 1 ? stops : []
        self.onMain {
            self.baseZoomFactor = base
            self.minZoomFactor = minF
            self.maxZoomFactor = maxF
            self.maxZoom = maxF
            self.zoomStops = published
            self.zoomFactor = base
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

    /// Set the zoom factor. `ramp` animates the change (used by lens-button taps
    /// so the optical lens switch glides); pinch passes `false` for 1:1 tracking.
    func setZoom(_ factor: CGFloat, ramp: Bool = false) {
        let clamped = max(minZoomFactor, min(factor, maxZoomFactor))
        zoomFactor = clamped
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                if ramp {
                    device.ramp(toVideoZoomFactor: clamped, withRate: 24)
                } else {
                    device.cancelVideoZoomRamp()
                    device.videoZoomFactor = clamped
                }
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

    // MARK: Photo / video mode

    /// True when photo↔video needs no session reconfiguration (the movie output
    /// shares the `.photo` preset), so the UI can switch instantly with no cover.
    var switchIsInstant: Bool { movieUnderPhoto }

    /// `completion` fires on the main thread once the session has settled. In the
    /// instant path it fires immediately (no reconfiguration at all).
    func setMediaMode(_ m: CaptureMediaMode, completion: @escaping () -> Void = {}) {
        guard m != mediaMode else { completion(); return }
        mediaMode = m
        liveGrade = (m == .photo)
        // Instant path: no session change — immediate, like the native Camera.
        // Video records at the shared `.photo` (4:3) framing.
        guard configured, !movieUnderPhoto else { completion(); return }
        // Fallback (devices that only allow the movie output under `.high`): swap
        // the preset. Slower, so the UI covers this transition.
        let mirror = (position == .front)
        sessionQueue.async { [weak self] in
            guard let self else { DispatchQueue.main.async(execute: completion); return }
            self.session.beginConfiguration()
            if m == .video {
                if self.session.canSetSessionPreset(.high) { self.session.sessionPreset = .high }
                if !self.movieAdded, self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                    self.movieAdded = true
                }
            } else {
                // Keep the movie output attached (fast future switches). Only pull
                // it if this device won't accept the `.photo` preset alongside it.
                if self.session.canSetSessionPreset(.photo) {
                    self.session.sessionPreset = .photo
                } else if self.movieAdded {
                    self.session.removeOutput(self.movieOutput); self.movieAdded = false
                    if self.session.canSetSessionPreset(.photo) { self.session.sessionPreset = .photo }
                }
            }
            self.session.commitConfiguration()
            // A preset change can reset the connections — re-orient after commit.
            self.applyConnectionGeometry(front: mirror)
            // Refresh the max clamp for the (possibly new) format without disturbing
            // the current zoom or the lens stops.
            let maxZ = min(self.videoDevice?.maxAvailableVideoZoomFactor ?? 1, self.baseZoomFactor * 15)
            self.onMain { self.maxZoom = maxZ; self.maxZoomFactor = maxZ; completion() }
        }
    }

    /// Whether the VIDEO toggle should be offered (session is up on a real camera).
    var canRecordVideo: Bool { videoCapable }

    /// Start recording a movie to a temp file. `completion` fires on the main
    /// thread with the finished file URL (or nil on failure) once recording ends.
    func startRecording(completion: @escaping (URL?) -> Void) {
        guard configured else { completion(nil); return }
        // Debounce on the main thread: ignore a second tap while a start is already
        // pending or a recording is active (`isRecording` only flips later, on the
        // session queue, so it can't gate this on its own).
        guard !recordPending else { return }
        recordPending = true
        recordHandler = completion
        let mirror = (position == .front)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.movieAdded, !self.movieOutput.isRecording else {
                self.onMain { self.recordPending = false; let h = self.recordHandler; self.recordHandler = nil; h?(nil) }
                return
            }
            // Adding the mic rebuilds connections, so re-orient afterwards.
            self.ensureAudioInput()
            self.applyConnectionGeometry(front: mirror)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            self.onMain { self.isRecording = true }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    /// Add the microphone input the first time it's needed, so photo-only users
    /// are never prompted for mic access. Call on the session queue.
    private func ensureAudioInput() {
        guard !audioAdded,
              let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.addInput(input)
        session.commitConfiguration()
        audioAdded = true
    }

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
        // Grain rides with the film look automatically (each look carries its own
        // amount; Original has none) — no separate toggle. Preview stays grain-free.
        let processed = CameraProcessing.apply(to: ci, keystone: keystone, look: look, grain: true)
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
        let front = (position == .front)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.pendingKeystone = keystone
            self.pendingLook = look
            self.pendingCropRatio = cropRatio
            self.pendingFront = front
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
              var image = UIImage(data: data) else {
            onMain { self.deliver(nil) }
            return
        }
        // The app frames portrait-only, but the front camera's photo connection —
        // like its preview connection — claims the 90° rotation and then delivers
        // unrotated landscape pixels stamped as already-upright, so the saved
        // selfie came out sideways. Normalize EXIF first; if the still is somehow
        // still landscape, stand it upright ourselves.
        //
        // `.left` (not `.right`): the viewfinder needs the opposite constant for
        // the same sensor because CoreImage's y-axis is flipped relative to
        // UIKit's, so a rotation that reads clockwise in one reads anticlockwise
        // in the other. Using `.right` here landed the photo upside down.
        //
        // The back camera honours the rotation, arrives portrait, and skips this.
        image = CameraController.normalized(image)
        if image.size.width > image.size.height, let cg = image.cgImage {
            image = CameraController.normalized(UIImage(cgImage: cg, scale: 1, orientation: .left))
        }
        // Un-mirror the selfie. This front camera ignores the connection's
        // mirroring setting (as it ignores rotation), so it saves mirrored
        // regardless — flip it back here so a saved selfie reads naturally (text
        // the right way round), matching how others see you.
        if pendingFront, let cg = image.cgImage {
            image = CameraController.normalized(UIImage(cgImage: cg, scale: image.scale, orientation: .upMirrored))
        }
        // Skip the whole Core Image round-trip when there's nothing to grade
        // (no colour look, no tilt) — the common case. This alone cut a big chunk
        // off the shutter-to-preview delay.
        let ks = pendingKeystone ?? 0
        let processed = (pendingLook == .original && ks == 0)
            ? image
            : processedStill(image, keystone: ks, look: pendingLook)
        let cropped = CameraController.crop(processed, toRatio: ratio)
        let jpeg = cropped.jpegData(compressionQuality: 0.9)
        onMain { self.deliver(jpeg) }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // A non-nil error can still accompany a fully usable file (e.g. the
        // recording was ended by an interruption such as an incoming call);
        // AVFoundation signals that via the success key, so keep the clip.
        let finishedOK = error == nil
            || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        onMain {
            self.isRecording = false
            self.recordPending = false
            let handler = self.recordHandler
            self.recordHandler = nil
            handler?(finishedOK ? outputFileURL : nil)
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let bw = CVPixelBufferGetWidth(pb), bh = CVPixelBufferGetHeight(pb)

        // Hold the last good frame until the incoming camera's frames match its
        // settled geometry — during a flip it briefly delivers frames that don't,
        // which flashed a wrongly-oriented image.
        if awaitingSettledFrame {
            let settled = liveFront ? (bw > bh) : (bh > bw)
            if settled || CFAbsoluteTimeGetCurrent() > settleDeadline {
                awaitingSettledFrame = false
            } else {
                return
            }
        }

        // The viewfinder owns its own geometry, because the connection can't be
        // trusted with it: the front camera *accepts* the portrait rotation —
        // reporting back 90° — then ignores it (measured: its frames arrive
        // landscape while the back camera's arrive portrait), and AVFoundation does
        // not auto-mirror this output either. So the connection is pinned to
        // "never mirror" and we do both here. Stills and movies are unaffected —
        // they carry the connection's stated rotation as EXIF / a track transform.
        var raw = CIImage(cvPixelBuffer: pb)
        // Mirror BEFORE rotating: mirroring after the rotation differs by a vertical
        // flip, i.e. an upside-down frame.
        if liveFront {
            let e = raw.extent
            raw = raw.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .concatenating(CGAffineTransform(translationX: e.minX + e.maxX, y: 0)))
        }
        if raw.extent.width > raw.extent.height {
            raw = raw.oriented(.right)
        }
        raw = raw.transformed(by: CGAffineTransform(translationX: -raw.extent.minX,
                                                    y: -raw.extent.minY))
        // Grain off for the live preview — it's baked into the captured photo only.
        // In video mode grading is skipped so the preview matches the straight movie.
        let look = liveGrade ? liveLook : .original
        let ks = liveGrade ? liveKeystone : 0
        let processed = CameraProcessing.apply(to: raw, keystone: ks, look: look, grain: false)
        DispatchQueue.main.async { [weak self] in
            self?.metalView?.update(processed)
            self?.latestFrame = raw
        }
    }
}
