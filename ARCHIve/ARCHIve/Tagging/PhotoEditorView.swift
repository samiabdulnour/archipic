import SwiftUI
import SwiftData
import CoreImage
import Metal

/// Non-destructive photo editor: rotate / crop / tilt / colour look. Edits are
/// stored as parameters on the Photo (applied on display), so the original is
/// never altered and everything is reversible.
struct PhotoEditorView: View {
    @Bindable var photo: Photo
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var look: CameraLook = .original
    @State private var keystone: Double = 0
    @State private var rotation: Int = 0
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var tool: Tool = .crop

    @State private var source: UIImage?     // raw (upright), preview resolution
    @State private var preview: UIImage?    // source + rotation + tilt + look (no crop)
    @State private var keystoneWasZero = true
    @State private var moveStart: CGRect?   // crop at the start of a move-drag
    @State private var renderSeq = 0        // drop stale async renders

    enum Tool: String, CaseIterable { case crop = "Crop", tilt = "Tilt", color = "Color" }
    private enum Corner { case tl, tr, bl, br }

    // Metal-backed (matches the live camera path, which renders these looks fine).
    private static let ciContext: CIContext = {
        if let dev = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: dev) }
        return CIContext()
    }()
    // Serial queue so renders never overlap on the shared context.
    private static let renderQueue = DispatchQueue(label: "archive.editor.render")

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                imageArea(in: geo.size)
            }
            .background(Color.black)
            toolPicker
            toolControls
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task {
            look = CameraLook(rawValue: photo.editLookRaw ?? "") ?? .original
            keystone = photo.editKeystone
            rotation = photo.editRotation
            crop = CGRect(x: photo.cropX, y: photo.cropY, width: photo.cropW, height: photo.cropH)
            keystoneWasZero = keystone == 0
            await loadSource()
            recompute()
        }
        .onChange(of: look) { _, _ in recompute() }
        .onChange(of: keystone) { _, _ in recompute() }
        .onChange(of: rotation) { _, _ in recompute() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button("Cancel") { onDone(); dismiss() }
            Spacer()
            Button("Reset") { resetEdits() }
                .disabled(look == .original && keystone == 0 && rotation == 0 && crop == .init(x: 0, y: 0, width: 1, height: 1))
            Spacer()
            Button("Save") { save() }.fontWeight(.semibold)
        }
        .tint(Palette.coral)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color.black)
    }

    // MARK: Image area + crop overlay

    @ViewBuilder
    private func imageArea(in bounds: CGSize) -> some View {
        if let preview {
            let fit = fitRect(preview.size, in: bounds)
            let cr = screenRect(crop, in: fit)
            ZStack {
                Image(uiImage: preview)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)

                if tool == .crop {
                    // Dim outside the crop window (even-odd hole).
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: bounds))
                        p.addRect(cr)
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                    thirds(in: cr)
                    Rectangle().stroke(.white.opacity(0.9), lineWidth: 1)
                        .frame(width: cr.width, height: cr.height)
                        .position(x: cr.midX, y: cr.midY)
                        .allowsHitTesting(false)

                    // Drag the interior to move the whole crop.
                    Color.clear.contentShape(Rectangle())
                        .frame(width: cr.width, height: cr.height)
                        .position(x: cr.midX, y: cr.midY)
                        .gesture(moveGesture(fit: fit))

                    cornerHandle(.tl, cr, fit)
                    cornerHandle(.tr, cr, fit)
                    cornerHandle(.bl, cr, fit)
                    cornerHandle(.br, cr, fit)
                }
            }
            .frame(width: bounds.width, height: bounds.height)
        } else {
            ProgressView().tint(.white)
                .frame(width: bounds.width, height: bounds.height)
        }
    }

    private func thirds(in cr: CGRect) -> some View {
        Path { p in
            for i in 1...2 {
                let x = cr.minX + cr.width * CGFloat(i) / 3
                p.move(to: CGPoint(x: x, y: cr.minY)); p.addLine(to: CGPoint(x: x, y: cr.maxY))
                let y = cr.minY + cr.height * CGFloat(i) / 3
                p.move(to: CGPoint(x: cr.minX, y: y)); p.addLine(to: CGPoint(x: cr.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.4), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    private func cornerHandle(_ corner: Corner, _ cr: CGRect, _ fit: CGRect) -> some View {
        let pos: CGPoint
        switch corner {
        case .tl: pos = CGPoint(x: cr.minX, y: cr.minY)
        case .tr: pos = CGPoint(x: cr.maxX, y: cr.minY)
        case .bl: pos = CGPoint(x: cr.minX, y: cr.maxY)
        case .br: pos = CGPoint(x: cr.maxX, y: cr.maxY)
        }
        return Circle().fill(.white)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Palette.coral, lineWidth: 2))
            .position(pos)
            .gesture(cornerGesture(corner, fit: fit))
    }

    private func cornerGesture(_ corner: Corner, fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { v in
            let nx = clamp(Double((v.location.x - fit.minX) / fit.width))
            let ny = clamp(Double((v.location.y - fit.minY) / fit.height))
            var r = crop
            let minSize = 0.12
            switch corner {
            case .tl:
                let mx = min(nx, r.maxX - minSize), my = min(ny, r.maxY - minSize)
                r = CGRect(x: mx, y: my, width: r.maxX - mx, height: r.maxY - my)
            case .tr:
                let mx = max(nx, r.minX + minSize), my = min(ny, r.maxY - minSize)
                r = CGRect(x: r.minX, y: my, width: mx - r.minX, height: r.maxY - my)
            case .bl:
                let mx = min(nx, r.maxX - minSize), my = max(ny, r.minY + minSize)
                r = CGRect(x: mx, y: r.minY, width: r.maxX - mx, height: my - r.minY)
            case .br:
                let mx = max(nx, r.minX + minSize), my = max(ny, r.minY + minSize)
                r = CGRect(x: r.minX, y: r.minY, width: mx - r.minX, height: my - r.minY)
            }
            crop = r
        }
    }

    private func moveGesture(fit: CGRect) -> some Gesture {
        DragGesture().onChanged { v in
            if moveStart == nil { moveStart = crop }
            let start = moveStart ?? crop
            let dx = Double(v.translation.width / fit.width)
            let dy = Double(v.translation.height / fit.height)
            let x = min(max(0, start.minX + dx), 1 - start.width)
            let y = min(max(0, start.minY + dy), 1 - start.height)
            crop = CGRect(x: x, y: y, width: start.width, height: start.height)
        }
        .onEnded { _ in moveStart = nil }
    }

    // MARK: Tool picker + controls

    private var toolPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tool.allCases, id: \.self) { t in
                Button { tool = t } label: {
                    Text(t.rawValue.uppercased())
                        .font(.system(size: 12, weight: tool == t ? .bold : .regular))
                        .tracking(1)
                        .foregroundStyle(tool == t ? Palette.lemon : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var toolControls: some View {
        switch tool {
        case .crop:  cropControls
        case .tilt:  tiltControls
        case .color: colorControls
        }
    }

    private var cropControls: some View {
        HStack(spacing: 12) {
            // Rotate lives here as a compact icon — a crop-tab action, out of the way.
            Button { rotate90() } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 44, height: 36)
                    .background(Capsule().fill(.white.opacity(0.14)))
            }
            Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 24)
            // A short, essential set of ratios (orientation follows the photo).
            HStack(spacing: 8) {
                aspectButton("Free", nil)
                aspectButton("1:1", 1)
                aspectButton("4:3", 4.0 / 3.0)
                aspectButton("16:9", 16.0 / 9.0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func rotate90() {
        rotation = (rotation + 90) % 360
        crop = CGRect(x: 0, y: 0, width: 1, height: 1)   // reset crop on rotate
    }

    private func aspectButton(_ label: String, _ ar: CGFloat?) -> some View {
        Button { setAspect(ar) } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.14)))
        }
    }

    private var tiltControls: some View {
        Slider(value: Binding(
            get: { keystone },
            set: { raw in
                let v = abs(raw) < 0.07 ? 0 : raw
                if v == 0 && !keystoneWasZero { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
                keystoneWasZero = (v == 0)
                keystone = v
            }), in: -1...1)
            .tint(Palette.coral)
            .overlay(alignment: .center) { Rectangle().fill(.white.opacity(0.4)).frame(width: 1.5, height: 16) }
            .frame(maxWidth: 320)
    }

    private var colorControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CameraLook.allCases) { l in
                    Button { look = l } label: {
                        Text(l.rawValue.uppercased())
                            .font(.system(size: 12, weight: look == l ? .bold : .regular))
                            .tracking(0.8)
                            .foregroundStyle(look == l ? Palette.lemon : .white.opacity(0.6))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Capsule().fill(look == l ? .white.opacity(0.12) : .clear))
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Helpers

    private func clamp(_ v: Double) -> Double { min(max(0, v), 1) }

    private func fitRect(_ imgSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imgSize.width > 0, imgSize.height > 0, bounds.width > 0 else { return .zero }
        let s = min(bounds.width / imgSize.width, bounds.height / imgSize.height)
        let w = imgSize.width * s, h = imgSize.height * s
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    private func screenRect(_ norm: CGRect, in fit: CGRect) -> CGRect {
        CGRect(x: fit.minX + norm.minX * fit.width, y: fit.minY + norm.minY * fit.height,
               width: norm.width * fit.width, height: norm.height * fit.height)
    }

    private func setAspect(_ ar: CGFloat?) {
        guard let preview else { return }
        guard let ar else { crop = CGRect(x: 0, y: 0, width: 1, height: 1); return }
        let imgAR = preview.size.width / preview.size.height
        // Follow the photo's orientation: a portrait image gets the tall form of
        // the ratio (4:3 → 3:4), so the crop matches how the shot is framed.
        let ratio = imgAR < 1 ? 1 / ar : ar
        var w = 1.0, h = 1.0
        if ratio >= imgAR { h = Double(imgAR / ratio) } else { w = Double(ratio / imgAR) }
        crop = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    private func resetEdits() {
        look = .original; keystone = 0; rotation = 0
        crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        keystoneWasZero = true
    }

    private func loadSource() async {
        let base: UIImage?
        if let id = photo.assetLocalID, !id.isEmpty {
            base = await PhotosLibrary.image(localID: id, maxPixel: 1600)
        } else {
            base = UIImage(data: photo.imageData)
        }
        source = base.map(normalizedUp)
    }

    /// Rebuild the preview on a serial background queue (never overlapping):
    /// source + rotation + tilt + look (crop is an overlay). Only the latest
    /// render is applied.
    private func recompute() {
        renderSeq += 1
        let seq = renderSeq
        let src = source, rot = rotation, ks = keystone, lk = look
        Self.renderQueue.async {
            guard let src, let cg = src.cgImage else { return }
            var ci = CIImage(cgImage: cg)
            if rot % 360 != 0 {
                ci = ci.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(rot) * .pi / 180))
                ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
            }
            ci = CameraProcessing.apply(to: ci, keystone: ks, look: lk, grain: Settings.grainEnabled)
            guard let out = Self.ciContext.createCGImage(ci, from: ci.extent) else { return }
            let img = UIImage(cgImage: out)
            Self.ciContext.clearCaches()   // don't let rapid re-renders accumulate
            DispatchQueue.main.async { if seq == renderSeq { preview = img } }
        }
    }

    private func normalizedUp(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let r = UIGraphicsImageRenderer(size: image.size)
        return r.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    private func save() {
        photo.editLookRaw = look == .original ? nil : look.rawValue
        photo.editKeystone = keystone
        photo.editRotation = rotation
        photo.cropX = crop.minX; photo.cropY = crop.minY
        photo.cropW = crop.width; photo.cropH = crop.height
        try? modelContext.save()
        onDone(); dismiss()
    }
}
