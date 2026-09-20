import SwiftUI
import SwiftData
import AVFoundation

struct CameraView: View {
    /// Pre-selected project from a Shortcuts / Siri / Action-Button capture.
    var initialProject: String? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Photo.createdAt, order: .reverse) private var allPhotos: [Photo]

    @State private var camera = CameraController()
    @State private var motion = MotionLevel()

    @State private var countdown: Int?
    @State private var shutterFlash = false
    @State private var savedCount = 0
    @State private var tagTarget: Photo?

    @State private var tagMode: TagMode = .full

    // Lite-mode "Saved" toast
    @State private var savedToast: Photo?
    @State private var savedToastIsVideo = false
    @State private var toastHideItem: DispatchWorkItem?
    @State private var showSettings = false
    @State private var showProjectPicker = false
    @State private var tool: CameraTool = .none
    @State private var keystoneWasZero = true       // for the tilt slider's centre-snap haptic
    @State private var mediaSwitching = false        // masks the photo↔video session reconfig
    /// Physical screen size (incl. safe areas) — used to crop full-bleed captures
    /// to the exact on-screen ratio.
    @State private var screenSize: CGSize = .zero

    enum CameraTool { case none, looks, keystone }

    enum TagMode { case lite, full }

    private var latest: Photo? { allPhotos.first }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if camera.authorized {
                    previewStack(in: geo)
                } else if camera.permissionDenied {
                    permissionView
                } else {
                    ProgressView().tint(.white)
                }
            }
            .overlay(alignment: .top) { savedToastView }
            // Cover the feed while photo↔video reconfigures the session, so the
            // preview freeze + layout shift read as one clean transition.
            .overlay {
                Color.black.ignoresSafeArea()
                    .opacity(mediaSwitching ? 1 : 0)
                    .allowsHitTesting(mediaSwitching)
            }
            .onAppear { updateScreenSize(geo) }
            .onChange(of: geo.size) { _, _ in updateScreenSize(geo) }
        }
        .statusBarHidden(true)
        .onAppear {
            camera.requestAccessAndConfigure()
            motion.start()
            LocationProvider.shared.start()
            // A Shortcut / Siri / Action-Button capture can pre-select a project.
            if let p = initialProject { camera.currentProject = p }
            lockToPortrait()   // the viewfinder is portrait-only (see AppOrientation)
        }
        .onDisappear {
            camera.stop()
            motion.stop()
            LocationProvider.shared.stop()
            releaseOrientation()
        }
        .fullScreenCover(item: $tagTarget, onDismiss: { camera.start() }) { photo in
            TagSheetView(photo: photo) { tagTarget = nil }
        }
        .sheet(isPresented: $showSettings) {
            CameraSettingsSheet(camera: camera, tagMode: $tagMode)
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(projects: existingProjects, current: camera.currentProject) { name in
                // Never store an empty/blank name — unfiled is nil.
                let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                camera.currentProject = n.isEmpty ? nil : n
            }
        }
    }

    /// Pin the app to portrait while the viewfinder is up (iPad can otherwise be
    /// landscape), and snap the interface to portrait now if it was landscape.
    private func lockToPortrait() {
        AppOrientation.cameraActive = true
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// Let the app rotate freely again after the camera closes (iPad).
    private func releaseOrientation() {
        AppOrientation.cameraActive = false
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func updateScreenSize(_ geo: GeometryProxy) {
        screenSize = CGSize(width: geo.size.width,
                            height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
    }

    /// The portrait ratio (w/h) the capture should be cropped to so it matches
    /// what the preview shows: the chosen aspect in framed modes, the actual
    /// screen ratio in full-bleed (16:9) mode.
    private func currentCropRatio() -> CGFloat {
        if camera.aspect == .sixteenNine, screenSize.height > 0 {
            return screenSize.width / screenSize.height
        }
        return camera.aspect.portraitRatio
    }

    private var existingProjects: [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in allPhotos { if let n = p.project, !n.isEmpty, seen.insert(n).inserted { out.append(n) } }
        return Set(out).union(Settings.customProjects).sorted()
    }

    // MARK: Preview + overlays

    @ViewBuilder
    private func previewStack(in geo: GeometryProxy) -> some View {
        // Native-style layout: the live feed stays full-bleed, but the *crop
        // window* sits in the region above the controls (not centred on the
        // whole screen), so its bottom edge never collides with the shutter.
        // The zoom bar rides the bottom edge of that window and moves with the
        // chosen ratio, exactly like the system Camera.
        // 16:9 is the full-bleed mode (like native): the feed fills the screen
        // edge-to-edge and the controls float over it. 4:3 / 1:1 use a framed
        // crop window with the area outside dimmed.
        // Photo and video share the chosen aspect, so switching never reframes
        // (seamless). Video records the full sensor and the aspect is applied as
        // a framing crop (preview + poster + aspect-fill playback).
        let isFullBleed = camera.aspect == .sixteenNine
        let ratio = camera.aspect.portraitRatio          // width / height (<1)
        let topSafe = geo.safeAreaInsets.top
        let botSafe = geo.safeAreaInsets.bottom
        let fullW = geo.size.width
        let fullH = geo.size.height + topSafe + botSafe   // physical screen height
        let topReserve = topSafe + 74                     // top pill row + breathing room so the frame sits a little lower
        // CONSTANT reserve — the capture frame never changes size, in any tool
        // state. The tool pickers swap into the fixed control band below the
        // shutter (same height as the normal row), so nothing moves.
        let bottomReserve = botSafe + 172
        let availH = max(0, fullH - topReserve - bottomReserve)
        let frameH = min(availH, fullW / ratio)
        let frameW = min(fullW, frameH * ratio)
        let frameCx = fullW / 2
        let frameTop = topReserve + (availH - frameH) / 2
        let frameCy = frameTop + frameH / 2
        let frameBottom = frameTop + frameH

        ZStack {
            // The live feed renders INSIDE the framing window (framed modes) so
            // what's shown is the exact crop that gets saved. Full-bleed (16:9)
            // fills the whole screen. Capture crops to the same region.
            if isFullBleed {
                MetalCameraPreview(controller: camera)
                    .ignoresSafeArea()
            } else {
                MetalCameraPreview(controller: camera)
                    .frame(width: frameW, height: frameH)
                    .position(x: frameCx, y: frameCy)
            }

            if isFullBleed {
                // No crop window: full-screen grid + centred level, controls
                // float over the feed (zoom lives in the bottom inset below).
                if camera.gridOn { GridOverlay().ignoresSafeArea() }
                if camera.levelOn && !motion.isFlat {
                    LevelOverlay(angle: motion.angle, isLevel: motion.isLevel)
                }
            } else {
                // Dim everything outside the crop window, punching a clear hole.
                ZStack {
                    Color.black.opacity(0.4)
                    Rectangle()
                        .frame(width: frameW, height: frameH)
                        .position(x: frameCx, y: frameCy)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)

                if camera.gridOn {
                    GridOverlay()
                        .frame(width: frameW, height: frameH)
                        .position(x: frameCx, y: frameCy)
                }
                if camera.levelOn && !motion.isFlat {
                    LevelOverlay(angle: motion.angle, isLevel: motion.isLevel)
                        .position(x: frameCx, y: frameCy)
                }
            }

            // Tap-to-focus + drag-to-expose, in its own full-screen space so the
            // reticle lands exactly under the finger. Hosts the pinch-zoom too.
            // Focus only registers inside the crop frame (whole screen in 16:9).
            FocusExposureView(
                camera: camera,
                focusRegion: isFullBleed
                    ? CGRect(x: 0, y: 0, width: fullW, height: fullH)
                    : CGRect(x: frameCx - frameW / 2, y: frameCy - frameH / 2, width: frameW, height: frameH)
            )

            // Framed-mode zoom bar rides the crop window's bottom edge — kept
            // ABOVE the focus overlay so tapping a factor zooms (not focuses).
            // Hidden while a tool picker is open (same rule as full-bleed): the
            // look name sits in that exact spot, so the two would collide.
            if !isFullBleed && showsZoomControl && tool == .none {
                zoomControl.position(x: frameCx, y: frameBottom - 26)
            }

            if shutterFlash { Color.black.ignoresSafeArea() }
            if let c = countdown {
                Text("\(c)").font(.system(size: 120, weight: .thin, design: .rounded))
                    .foregroundStyle(.white).shadow(radius: 8)
                    .position(x: frameCx, y: isFullBleed ? fullH / 2 : frameCy)
            }

            // Recording is signalled by the spinning record button alone (see
            // CaptureMark) — no frame around the viewfinder.

            // Film-look name + weather over the bottom of the frame while picking
            // (native-Camera style — inside the preview, not below it).
            if tool == .looks {
                lookNameChip
                    .position(x: frameCx,
                              y: isFullBleed ? (fullH - bottomReserve - 6) : (frameBottom - 34))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .top) {
                projectPill
                Spacer()
                actionPill
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 16) {
                // Zoom bar floats above the shutter in full-bleed; hidden while a
                // tool picker is open to keep the area clean.
                if isFullBleed && showsZoomControl && tool == .none { zoomControl }
                // Shutter — fixed position in every state.
                if camera.mediaMode == .video { recordButton } else { shutterButton }
                // Fixed-height band UNDER the shutter: the normal controls, or the
                // active tool's picker (film-look swatches / tilt), native-Camera
                // style. Same height in every state ⇒ frame & shutter never move.
                bottomBand
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 6)
            // Scrim so the floating controls stay legible over a bright feed.
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            )
        }
    }

    // MARK: Top — action pill (film look, tilt, more)

    private var actionPill: some View {
        HStack(spacing: 8) {
            // Photo-only: the film look (Colours) and tilt, each opening a tray
            // above the shutter. Colours is a top-level control now (was buried in
            // the settings sheet). Hidden for video — the look/tilt pipeline is
            // stills-only — fading rather than popping so the pill reflows smoothly.
            if camera.mediaMode == .photo {
                pillButton("camera.filters", active: camera.colorLook != .original) {
                    withAnimation(.easeInOut(duration: 0.2)) { tool = (tool == .looks) ? .none : .looks }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                pillButton("skew", active: camera.keystoneStrength != 0) {
                    withAnimation(.easeInOut(duration: 0.2)) { tool = (tool == .keystone) ? .none : .keystone }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
            // More — flash / timer / aspect / grid / level / tag mode / settings.
            pillButton("circle.grid.3x3.fill", active: false) {
                showSettings = true
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .animation(.easeInOut(duration: 0.22), value: camera.mediaMode)
    }

    private func pillButton(_ symbol: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? Palette.coral : .white)
                .rotatingIcon(motion.iconAngle)
                .frame(width: 32, height: 32)
        }
    }

    /// Project mode replaces the Type segment with a Pick-project pill
    /// (matches the old app); tap to choose / change the project.
    /// The project a shot is filed into; nil = unfiled (blank names count as
    /// unfiled, so the pill can never show an empty label).
    private var filedProject: String? {
        let name = (camera.currentProject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Unfiled shows just the folder icon (matches the gallery's Project lens);
    /// once a project is chosen the pill grows to carry its name, and the folder
    /// fills in lemon to read as "filed".
    private var projectPill: some View {
        Button { showProjectPicker = true } label: {
            HStack(spacing: 7) {
                Image(systemName: filedProject == nil ? "folder" : "folder.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(filedProject == nil ? .white : Palette.lemon)
                    .rotatingIcon(motion.iconAngle)
                if let filedProject {
                    Text(filedProject)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, filedProject == nil ? 0 : 12)
            .frame(width: filedProject == nil ? 35 : nil, height: 35)
            .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        }
        .accessibilityLabel(filedProject ?? "Pick project")
        .animation(.easeInOut(duration: 0.2), value: filedProject)
    }

    // MARK: Bottom — shutter, mode toggle, thumbnail, flip

    private var shutterButton: some View {
        // The app mark as a shutter: the App Store icon's dash-dot-dot ring around
        // a filled disc, in white. Springy press-shrink for tactility.
        Button(action: onShutter) {
            CaptureMark(color: .white)
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(countdown != nil)
    }

    /// PHOTO / VIDEO — the native Camera-style capture toggle. VIDEO only shows
    /// when the device allowed the movie output.
    private var mediaModeToggle: some View {
        HStack(spacing: 18) {
            modeSegment("PHOTO", on: camera.mediaMode == .photo, tint: Palette.lemon) {
                switchMedia(.photo)
            }
            if camera.canRecordVideo {
                modeSegment("VIDEO", on: camera.mediaMode == .video, tint: Palette.lemon) {
                    switchMedia(.video)
                }
            }
        }
    }

    private func switchMedia(_ m: CaptureMediaMode) {
        guard m != camera.mediaMode, !mediaSwitching else { return }
        tool = .none   // close any looks/tilt tray
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if camera.switchIsInstant {
            camera.setMediaMode(m)   // no reconfiguration → immediate, no cover
        } else {
            // Fallback devices reconfigure the session; mask it behind a cover.
            mediaSwitching = true
            camera.setMediaMode(m) {
                withAnimation(.easeOut(duration: 0.22)) { mediaSwitching = false }
            }
        }
    }

    /// Record button (video mode): the same app mark in the app's coral red; while
    /// recording, its ring spins (the disc is unchanged) — the sole record signal.
    private var recordButton: some View {
        Button(action: onRecordTap) {
            CaptureMark(color: Palette.coral, recording: camera.isRecording)
        }
        .buttonStyle(ShutterButtonStyle())
    }

    /// Native VIDEO/PHOTO-style label: uppercase, tracked, active highlighted.
    private func modeSegment(_ title: String, on: Bool, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(on ? tint : .white.opacity(0.6))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? Capsule().fill(.white.opacity(0.14)) : Capsule().fill(.clear))
        }
    }

    private var thumbnailButton: some View {
        Button { dismiss() } label: {
            Group {
                if let latest {
                    PhotoThumbnail(photo: latest).frame(width: 46, height: 46)
                } else {
                    Color.white.opacity(0.12).frame(width: 46, height: 46)
                        .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.7)))
                }
            }
            .rotatingIcon(motion.iconAngle)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.5), lineWidth: 1))
        }
    }

    private var flipButton: some View {
        Button { camera.flipCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .rotatingIcon(motion.iconAngle)
                .frame(width: 46, height: 46)
                .background(Circle().fill(.white.opacity(0.16)))
        }
    }

    /// Shown when the device offers more than one lens/zoom stop (multi-lens, or
    /// a 48-MP-crop 2×). Single-lens phones with no stops just pinch to zoom.
    private var showsZoomControl: Bool { camera.zoomStops.count > 1 }

    /// Native-Camera lens/zoom switcher: a row of real stops (0.5× / 1× / 2× / 5×)
    /// derived from the device's lenses. The active stop shows the live "×" while
    /// pinched; tapping a stop ramps the virtual camera to it (seamless optical
    /// switch). Pinch (in FocusExposureView) zooms continuously across all lenses.
    private var zoomControl: some View {
        HStack(spacing: 3) {
            ForEach(camera.zoomStops) { stop in
                let active = abs(camera.activeStopFactor - stop.factor) < 0.001
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    camera.setZoom(stop.factor, ramp: true)
                } label: {
                    Text(active ? "\(camera.displayZoomLabel)×" : stop.label)
                        .font(.system(size: active ? 15 : 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(active ? Palette.lemon : .white)
                        .shadow(color: .black.opacity(active ? 0 : 0.45), radius: 2)
                        // Each number turns in place as the phone does; the bar itself
                        // stays put. Rotating the whole bar stood it on end in landscape,
                        // stacking the stops on top of each other.
                        .rotatingIcon(motion.iconAngle)
                        .frame(width: active ? 46 : 32, height: 34)
                        .background(Circle().fill(.black.opacity(active ? 0.55 : 0)))
                        .scaleEffect(active ? 1 : 0.9)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.3)))
        .animation(.smooth(duration: 0.25), value: camera.activeStopFactor)
    }

    /// Lite-mode confirmation toast: "Saved · Tag later in gallery" with a
    /// one-tap "Tag now". Styled in the warm/mint palette of the old app.
    @ViewBuilder private var savedToastView: some View {
        if let photo = savedToast {
            HStack(spacing: 12) {
                Image(systemName: savedToastIsVideo ? "video.fill" : "photo")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(hex: "16140F"))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 11).fill(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(savedToastIsVideo ? "Video saved" : "Photo saved")
                        .font(.headline)
                        .foregroundStyle(Color(hex: "16140F"))
                    Text("Tag later in gallery")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "16140F").opacity(0.6))
                }
                Spacer(minLength: 8)
                Button {
                    toastHideItem?.cancel()
                    withAnimation(.easeInOut(duration: 0.2)) { savedToast = nil }
                    camera.stop()
                    tagTarget = photo
                } label: {
                    Text("Tag now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color(hex: "16140F")))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.mint))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            .padding(.horizontal, 12)
            .padding(.top, 58)   // clear the top control row
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// The fixed-height band directly under the shutter: normally the gallery /
    /// mode / flip row, but while a tool is active it becomes that tool's picker
    /// (film-look swatches or the tilt slider), native-Camera style. Every case is
    /// the same height, so swapping never moves the shutter or the frame.
    @ViewBuilder private var bottomBand: some View {
        switch tool {
        case .none:
            ZStack {
                HStack {
                    thumbnailButton.opacity(camera.isRecording ? 0.35 : 1)
                        .disabled(camera.isRecording)
                    Spacer()
                    flipButton.opacity(camera.isRecording ? 0.35 : 1)
                        .disabled(camera.isRecording)
                }
                // Hide the media toggle while recording (like the native Camera);
                // disable it during a self-timer countdown so the pending capture
                // can't fire in the wrong mode.
                if !camera.isRecording {
                    mediaModeToggle
                        .disabled(countdown != nil)
                        .opacity(countdown != nil ? 0.4 : 1)
                }
            }
        case .looks:
            HStack(spacing: 10) {
                trayCloseButton
                LooksStrip(camera: camera)
            }
        case .keystone:
            // Slider centred in the band so its 0 (off) tick sits exactly under
            // the shutter; the close button floats at the leading edge instead of
            // pushing the slider off-centre.
            ZStack {
                keystoneSlider
                HStack { trayCloseButton; Spacer() }
            }
        }
    }

    /// The selected look's name + its "best for" weather hint, shown directly
    /// above the swatch strip (like the native filter name).
    private var lookNameChip: some View {
        VStack(spacing: 1) {
            Text(camera.colorLook.rawValue.uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(1)
                .foregroundStyle(camera.colorLook == .original ? .white : Palette.lemon)
            Label(camera.colorLook.recommendation.text, systemImage: camera.colorLook.recommendation.icon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .id(camera.colorLook)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: camera.colorLook)
    }

    private var trayCloseButton: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { tool = .none } } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.16)))
        }
    }

    /// Strength control for the keystone correction. Snaps to the middle
    /// (0 = no tilt) so cancelling is one easy drag back to centre, and the
    /// centre tick sits exactly above the shutter.
    private var keystoneSlider: some View {
        Slider(value: Binding(
            get: { camera.keystoneStrength },
            set: { raw in
                let v = abs(raw) < 0.07 ? 0 : raw      // sticky centre detent
                if v == 0 && !keystoneWasZero {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
                keystoneWasZero = (v == 0)
                camera.setKeystoneStrength(v)
            }
        ), in: -1...1)
        .tint(Palette.coral)
        .overlay(alignment: .center) {
            // centre tick = 0 (no correction), aligned above the shutter
            Rectangle().fill(.white.opacity(0.4)).frame(width: 1.5, height: 16)
        }
        .frame(maxWidth: 280)
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 44)).foregroundStyle(.white)
            Text("Camera access needed").foregroundStyle(.white)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent).tint(Palette.coral)
        }
    }

    // MARK: Actions

    private func onShutter() {
        let secs = camera.timerSeconds
        if secs > 0 {
            // @MainActor: after the countdown await this resumes off-main otherwise,
            // mutating @State (shutterFlash/countdown) and capture bookkeeping on a
            // background thread.
            Task { @MainActor in await runCountdown(from: secs); performCapture() }
        } else {
            performCapture()
        }
    }

    private func runCountdown(from seconds: Int) async {
        for s in stride(from: seconds, through: 1, by: -1) {
            countdown = s
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        countdown = nil
    }

    private func performCapture() {
        // A quick shutter blink, decoupled from how long the capture takes —
        // previously the white overlay stayed up for the whole (~1s) capture.
        withAnimation(.easeIn(duration: 0.04)) { shutterFlash = true }
        Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            withAnimation(.easeOut(duration: 0.18)) { shutterFlash = false }
        }
        camera.capture(cropRatio: currentCropRatio(), iconAngle: motion.iconAngle) { data in
            guard let data else { return }
            let coord = LocationProvider.shared.last
            let proj = camera.currentProject
            Task { @MainActor in
                // Store the just-captured bytes and show the preview IMMEDIATELY —
                // the tag sheet / gallery render straight from imageData, so the
                // Photos write no longer sits on the shutter-to-preview path (the
                // slow part). The photo is never lost regardless.
                let photo = Photo(imageData: data,
                                  latitude: coord?.latitude, longitude: coord?.longitude,
                                  humanTags: prefilledTags(), project: proj, isCameraShot: true)
                modelContext.insert(photo)
                try? modelContext.save()
                savedCount += 1
                if tagMode == .full {
                    camera.stop()
                    tagTarget = photo
                } else {
                    // Lite mode: no tag sheet — confirm with a toast offering a
                    // one-tap "Tag now" (like the old app).
                    showSavedToast(photo)
                }
                // In the background, move the pixels into Photos and switch this
                // record to a reference (one copy, no duplicate) — off the hot
                // path so it never delays the preview. If Photos isn't permitted,
                // the shot simply stays owned in-app.
                Task.detached(priority: .utility) {
                    guard let localID = await PhotosLibrary.saveImage(data, coordinate: coord) else { return }
                    await MainActor.run {
                        // The owned Photo may have been deleted while the Photos
                        // write was in flight; mutating a deleted SwiftData model
                        // throws an uncatchable ObjC exception, so bail if it's gone
                        // (its context is cleared once delete+save has run).
                        guard photo.modelContext != nil else { return }
                        photo.assetLocalID = localID
                        photo.imageData = Data()   // pixels now live in Photos
                        try? modelContext.save()
                    }
                }
            }
        }
    }

    /// Start/stop a video recording. On finish the movie is saved and archived.
    private func onRecordTap() {
        if camera.isRecording {
            camera.stopRecording()
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            camera.startRecording { url in
                guard let url else { return }
                saveVideo(from: url)
            }
        }
    }

    /// Save a finished recording: into Photos as a reference when permitted (the
    /// poster still comes from the asset), otherwise keep the movie + poster
    /// in-app so the clip is never lost. Mirrors the still capture path.
    private func saveVideo(from url: URL) {
        let coord = LocationProvider.shared.last
        let proj = camera.currentProject
        let cropRatio = currentCropRatio()   // the framing to bake into the poster
        Task { @MainActor in
            // Poster = first frame, cropped to the chosen framing, so the gallery,
            // boards and thumbnail show the aspect you shot (the movie itself stays
            // full-sensor; playback aspect-fills to match). Stored even for library
            // references so the cropped still travels with the record.
            let posterFull = await VideoTools.posterFrame(from: url)
            let poster = posterFull.map { CameraController.crop($0, toRatio: cropRatio) }
            let posterData = poster?.jpegData(compressionQuality: 0.9) ?? Data()
            let localID = await PhotosLibrary.saveVideo(fileURL: url, coordinate: coord)
            // Fallback bytes only when Photos didn't take it.
            let movieData: Data? = localID == nil ? (try? Data(contentsOf: url)) : nil
            // Need a playable source — a Photos reference OR the in-app bytes.
            // If neither (Photos denied AND the file read failed), keep the temp
            // and abort rather than saving an unplayable phantom "video" and then
            // deleting its only copy.
            guard localID != nil || movieData != nil else { return }
            let photo: Photo
            if let localID {
                photo = Photo(imageData: posterData,
                              latitude: coord?.latitude, longitude: coord?.longitude,
                              humanTags: prefilledTags(), project: proj,
                              assetLocalID: localID, isCameraShot: true, isVideo: true)
            } else {
                photo = Photo(imageData: posterData,
                              latitude: coord?.latitude, longitude: coord?.longitude,
                              humanTags: prefilledTags(), project: proj,
                              isVideo: true, videoData: movieData)
            }
            modelContext.insert(photo)
            try? modelContext.save()
            savedCount += 1
            try? FileManager.default.removeItem(at: url)   // source persisted → temp no longer needed
            if tagMode == .full {
                camera.stop()
                tagTarget = photo
            } else {
                showSavedToast(photo)
            }
        }
    }

    private func showSavedToast(_ photo: Photo) {
        savedToastIsVideo = photo.isVideo
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { savedToast = photo }
        toastHideItem?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.3)) { savedToast = nil }
        }
        toastHideItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: item)
    }

    /// A fresh capture starts untagged — the Kind (building/element/graphic) and
    /// everything else is chosen later in tagging, not at capture.
    private func prefilledTags() -> HumanTags {
        HumanTags()
    }
}

// MARK: - Settings sheet (the "More" / ⋯ action)

private struct CameraSettingsSheet: View {
    @Bindable var camera: CameraController
    /// Tag immediately after each shot (Full) vs save-and-tag-later (Lite).
    @Binding var tagMode: CameraView.TagMode
    @Environment(\.dismiss) private var dismiss
    @State private var showAppSettings = false

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.3)).frame(width: 38, height: 5).padding(.vertical, 12)
            LazyVGrid(columns: cols, spacing: 22) {
                // Framing applies to both photo and video (shared aspect).
                item("ASPECT", "aspectratio", active: camera.aspect != .fourThree, badge: camera.aspect.rawValue) { cycleAspect() }
                // Stills-only controls (flash, timer).
                if camera.mediaMode == .photo {
                    item("FLASH", flashIcon, active: camera.flashMode != .off) { cycleFlash() }
                    item("TIMER", "timer", active: camera.timerSeconds != 0,
                         badge: camera.timerSeconds == 0 ? nil : "\(camera.timerSeconds)") { cycleTimer() }
                }
                // Tag now (opens tagging after each shot) vs tag later.
                item("TAG NOW", tagMode == .full ? "tag.fill" : "tag", active: tagMode == .full) {
                    tagMode = tagMode == .full ? .lite : .full
                }
                item("GRID", "grid", active: camera.gridOn) { camera.gridOn.toggle() }
                item("LEVEL", "level", active: camera.levelOn) { camera.levelOn.toggle() }
            }
            .padding(.horizontal, 22)
            // Settings on its own row, centred under the Grid button.
            item("SETTINGS", "gearshape", active: false) { showAppSettings = true }
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showAppSettings) { SettingsView() }
        .presentationDetents([.height(330)])
        // Liquid-glass: a forced-dark frosted material so the blurred feed
        // shows through, like the native Camera control sheet.
        .presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.18)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    private var timerSeconds: Int { camera.timerSeconds }
    private var flashIcon: String {
        switch camera.flashMode {
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        default: return "bolt.slash.fill"
        }
    }

    private func cycleFlash() {
        switch camera.flashMode {
        case .off: camera.flashMode = .auto
        case .auto: camera.flashMode = .on
        default: camera.flashMode = .off
        }
    }
    private func cycleTimer() {
        camera.timerSeconds = camera.timerSeconds == 0 ? 3 : (camera.timerSeconds == 3 ? 10 : 0)
    }
    private func cycleAspect() {
        let all = CaptureAspect.allCases
        if let i = all.firstIndex(of: camera.aspect) { camera.aspect = all[(i + 1) % all.count] }
    }

    @ViewBuilder
    private func item(_ label: String, _ symbol: String, active: Bool,
                      badge: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(active ? AnyShapeStyle(Palette.lemon) : AnyShapeStyle(.ultraThinMaterial))
                        .overlay(Circle().strokeBorder(active ? .clear : .white.opacity(0.25), lineWidth: 1))
                        .frame(width: 60, height: 60)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(active ? .black : .white)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(active ? .black : .white)
                    }
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Project picker

private struct ProjectPickerSheet: View {
    let projects: [String]
    let current: String?
    /// nil = shoot unfiled (no project).
    var onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                // Shoot without a project (the default for out-in-the-world finds).
                Button { onPick(nil); dismiss() } label: {
                    HStack {
                        Text("Unfiled").foregroundStyle(Palette.ink)
                        Spacer()
                        if (current ?? "").isEmpty { Image(systemName: "checkmark").foregroundStyle(Palette.coral) }
                    }
                }
                if !projects.isEmpty {
                    Section("Projects") {
                        ForEach(projects, id: \.self) { p in
                            Button { onPick(p); dismiss() } label: {
                                HStack {
                                    Text(p).foregroundStyle(Palette.ink)
                                    Spacer()
                                    if p == current { Image(systemName: "checkmark").foregroundStyle(Palette.coral) }
                                }
                            }
                        }
                    }
                }
                Section("New project") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Add") {
                            let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !n.isEmpty { onPick(n); dismiss() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Pick project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .tint(Palette.coral)
    }
}

// MARK: - Overlays

/// Rotates a control glyph to stay upright as the phone turns (native Camera
/// behaviour) while the UI itself stays locked in portrait.
private struct RotatingIcon: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .animation(.easeInOut(duration: 0.28), value: angle)
    }
}

private extension View {
    func rotatingIcon(_ angle: Double) -> some View { modifier(RotatingIcon(angle: angle)) }
}

/// Springy press-shrink for the shutter, like the native Camera.
private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// The app mark rendered as a capture control — the App Store icon's ISO 128
/// long-dash-double-dot ring around a filled disc, in the icon's exact
/// proportions (disc/ring diameter ratio and dash rhythm measured from the
/// 1024² source). White for photo, coral for video. While recording the button
/// is unchanged except the ring rotates. Keeps the old shutter's 72pt footprint.
private struct CaptureMark: View {
    var color: Color
    var recording = false
    var ring: CGFloat = 72

    /// Disc diameter = 0.911 × ring, straight from the icon (its disc nearly
    /// touches the ring — a tight, deliberate gap, not the wide one before).
    private var disc: CGFloat { ring * 0.911 }

    /// The icon's ring is 15 long-dash-double-dot repeats. Per 24° repeat: a
    /// 9.75° long dash, two 1.5° dots, three 3.75° gaps — reproduced here from
    /// the circumference so it tiles exactly at any ring size.
    private var dash: [CGFloat] {
        let c = CGFloat.pi * ring
        let long = c * 9.75 / 360
        let dot  = c * 1.5  / 360
        let gap  = c * 3.75 / 360
        return [long, gap, dot, gap, dot, gap]
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: dash))
                .frame(width: ring, height: ring)
                .rotationEffect(.degrees(recording ? 360 : 0))
                .animation(recording ? .linear(duration: 4).repeatForever(autoreverses: false)
                                     : .easeOut(duration: 0.3),
                           value: recording)
            Circle()
                .fill(color)
                .frame(width: disc, height: disc)
        }
    }
}

private struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 3
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// Artificial-horizon line through center that rotates with the phone, green
/// when level. Matches the web behaviour.
private struct LevelOverlay: View {
    let angle: Double
    let isLevel: Bool
    var body: some View {
        Rectangle()
            .fill(isLevel ? Palette.mint : Color.white.opacity(0.9))
            .frame(width: 120, height: 2)
            .rotationEffect(.degrees(-angle))
            .shadow(color: .black.opacity(0.4), radius: 1)
            // ~2 frames at 60 Hz: bridges samples smoothly without trailing lag.
            .animation(.linear(duration: 1.0 / 30.0), value: angle)
            .allowsHitTesting(false)
    }
}

/// Tap-to-focus + drag-to-expose, native-Camera style. Lives in its own
/// full-screen GeometryReader so the tap location and the reticle's `.position`
/// share one coordinate space (the reticle lands exactly under the finger), and
/// that space matches the full-bleed preview layer (so focus is accurate too).
/// Also hosts the pinch-to-zoom so all camera-feed gestures live together.
private struct FocusExposureView: View {
    let camera: CameraController
    /// The zoom factor captured at the start of a pinch, so the gesture scales
    /// from wherever the camera actually is (any lens), not a stale value.
    @State private var pinchAnchor: CGFloat?
    /// Taps that start outside this rect don't focus (the dimmed area in 4:3 /
    /// 1:1). Pinch-to-zoom still works anywhere.
    var focusRegion: CGRect

    @State private var point: CGPoint?
    @State private var bias: Float = 0
    @State private var visible = false
    @State private var gestureStarted = false
    @State private var ignoring = false
    @State private var hideItem: DispatchWorkItem?
    /// True while a pinch is recognized; a `@GestureState` auto-resets on end AND
    /// cancel (a plain flag wouldn't), so a cancelled pinch can't leave stale state.
    @GestureState private var pinching = false
    /// Pending tap-to-focus, deferred a beat so a second finger (pinch) cancels it.
    @State private var focusTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            if visible, let point {
                FocusReticle(bias: bias)
                    .position(point)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .gesture(focusDrag)
        .simultaneousGesture(zoomMagnify)
        // A pinch that ends OR is cancelled clears the anchor, so the next pinch
        // never scales from a stale value.
        .onChange(of: pinching) { _, now in if !now { pinchAnchor = nil } }
    }

    private var focusDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !gestureStarted {
                    gestureStarted = true
                    // Ignore the whole gesture if it began outside the frame.
                    ignoring = !focusRegion.contains(value.startLocation)
                    guard !ignoring else { return }
                    // First touch inside the frame = tap-to-focus at that point.
                    point = value.startLocation
                    bias = 0
                    // The preview layer is offset to the framing window, so map
                    // the screen tap into the window's coordinate space.
                    let lp = CGPoint(x: value.startLocation.x - focusRegion.minX,
                                     y: value.startLocation.y - focusRegion.minY)
                    // Defer focus a beat: a DragGesture(minimumDistance: 0) fires on
                    // the FIRST finger, including the first finger of a pinch, so
                    // committing focus immediately made every pinch-to-zoom yank
                    // focus/exposure to that point. If a second finger lands, the
                    // pinch cancels this task instead.
                    focusTask?.cancel()
                    focusTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 110_000_000)
                        guard !Task.isCancelled, !pinching else { return }
                        camera.focusAndExpose(atLayerPoint: lp)
                        camera.setExposureBias(0)
                        reveal()
                    }
                    return   // don't adjust exposure / reveal on the initial touch
                }
                // Subsequent moves = single-finger drag-to-expose (up brighter,
                // down darker, ≈90pt per EV). Skipped while pinching.
                guard !ignoring, !pinching else { return }
                let dy = value.location.y - value.startLocation.y
                bias = Float(max(-2, min(2, Double(-dy) / 90)))
                camera.setExposureBias(bias)
                reveal()
            }
            .onEnded { _ in
                gestureStarted = false
                ignoring = false
                scheduleHide()
            }
    }

    private var zoomMagnify: some Gesture {
        MagnifyGesture()
            .updating($pinching) { _, state, _ in state = true }
            .onChanged { value in
                focusTask?.cancel()   // a pinch cancels a pending tap-to-focus
                let anchor = pinchAnchor ?? camera.zoomFactor
                if pinchAnchor == nil { pinchAnchor = anchor }
                camera.setZoom(anchor * value.magnification)
            }
            .onEnded { _ in pinchAnchor = nil }
    }

    private func reveal() {
        hideItem?.cancel()
        if !visible { withAnimation(.easeOut(duration: 0.15)) { visible = true } }
    }

    private func scheduleHide() {
        hideItem?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.4)) { visible = false }
        }
        hideItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }
}

/// The yellow focus square with a sun that slides up/down as exposure changes —
/// the native tap-to-focus reticle.
private struct FocusReticle: View {
    let bias: Float
    private let box: CGFloat = 76

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Palette.lemon, lineWidth: 1)
                .frame(width: box, height: box)
            // Exposure sun on the right edge, sliding with the bias.
            Image(systemName: "sun.max.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.lemon)
                .shadow(color: .black.opacity(0.4), radius: 1)
                .offset(x: box / 2 + 16, y: CGFloat(-bias) * 22)
        }
        .allowsHitTesting(false)
    }
}
