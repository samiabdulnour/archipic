import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Cinematic colour looks. Each look is a *recipe* (see `buildRecipes`): a
/// white-balance shift, a per-hue signature (HSV colour-cube — what actually makes
/// one film stock differ from another, e.g. Portra's reds→orange vs Superia's
/// reds→crimson), and — the heart of the cinematic result — a COMPLEMENTARY
/// split-tone: shadows tinted one hue, highlights the opposite hue on the colour
/// wheel, so the grade reads like a film/cinema colour pass rather than a flat
/// temperature push. Blacks stay deep on every look (the split-tone keeps c0=0 and
/// the tone curve re-anchors true black last).
enum CameraLook: String, CaseIterable, Identifiable {
    case original  = "Original"
    case portra    = "Portra 400"      // sunny · warm — reds→orange, soft
    case superia   = "Superia 400"     // sunny · airy-white — reds→crimson, Fuji emerald
    case ektar     = "Ektar 100"       // vivid — bold clean colour
    case pro400h   = "Pro 400H"        // overcast · cold-airy — cyan-green, pastel
    case astia     = "Astia 100"       // overcast · warm-airy — soft warm-neutral
    case cinestill = "CineStill 800T"  // night · red — teal shadows, red halation
    case eterna    = "Eterna 500"      // night · greenish — green shadows, neon pop
    case trix      = "Tri-X 400"       // b&w · soft — gritty grain
    case acros     = "Acros 100"       // b&w · contrasted — crisp, dense skies
    var id: String { rawValue }

    /// One-line description shown in the camera, under the look's name.
    var blurb: String {
        switch self {
        case .original:  return "No look — the scene as captured."
        case .portra:    return "Warm and soft — reds glow to orange, peachy skin. Kodak's classic."
        case .superia:   return "Punchy Fuji — reds to crimson, emerald greens, airy whites."
        case .ektar:     return "Clean and bold — deep skies, electric greens, glowing reds."
        case .pro400h:   return "Soft, cool, pastel — cyan-greens, peachy-cool skin. Airy."
        case .astia:     return "Soft warm-neutral — gentle warmth, creamy diffusion."
        case .cinestill: return "Tungsten night — teal shadows, red-orange halation around lights."
        case .eterna:    return "Cinematic night — cold green-teal shadows, magenta-neon pop."
        case .trix:      return "Classic black & white — soft contrast, airy skies, rich grain."
        case .acros:     return "Fine-grain black & white — crisp, dramatic skies, dense blacks."
        }
    }

    /// When the look is at its best — a time-of-day / weather hint, with an SF Symbol.
    var recommendation: (icon: String, text: String) {
        switch self {
        case .original:  return ("circle.dashed", "Any conditions")
        case .portra:    return ("sun.haze", "Golden hour & soft daylight")
        case .superia:   return ("sun.max.fill", "Bright sun, blue skies, greenery")
        case .ektar:     return ("sun.max", "Bright sun, bold colour, clear skies")
        case .pro400h:   return ("cloud", "Overcast, open shade, soft light")
        case .astia:     return ("cloud.sun", "Overcast & open shade, warm light")
        case .cinestill: return ("moon.stars", "Night, neon & tungsten light")
        case .eterna:    return ("moon.stars.fill", "Night, city lights, dusk")
        case .trix:      return ("cloud.fog", "Overcast, gritty street")
        case .acros:     return ("sun.max", "Harsh sun & strong shadows")
        }
    }
}

enum CameraProcessing {
    static func apply(to input: CIImage, keystone: Double, look: CameraLook, grain: Bool = true) -> CIImage {
        var img = input
        if abs(keystone) > 0.01 { img = keystoned(img, strength: keystone) }
        img = colored(img, look: look, applyGrain: grain)
        return img
    }

    // MARK: Recipe

    /// One hue band of a look's per-hue signature: rotate hue by `rot`° and scale
    /// saturation/value within [lo,hi]°.
    private struct Band { var lo: Float; var hi: Float; var rot: Float; var sat: Float = 1; var val: Float = 1 }

    private struct Recipe {
        var wbTo: CGFloat = 6500            // temperature target from 6500 (>cooler, <warmer)
        // MEASURED (probe on grey, 2026-07-14): POSITIVE tint = GREEN, negative =
        // magenta — the opposite of what this comment used to claim. Every old
        // negative "green" tint was actually pushing magenta (Eterna's washed
        // look, part of Superia's red skin).
        var wbTint: CGFloat = 0             // green(+)/magenta(−)
        var bands: [Band] = []              // per-hue signature (the colour cube)
        var shadow = SIMD3<Float>(0, 0, 0)  // signed shadow tint per channel
        var highlight = SIMD3<Float>(0, 0, 0) // COMPLEMENTARY highlight tint
        var split: Float = 0                // split-tone strength
        var sat: Float = 1
        var con: Float = 1
        var curveY: [Double] = [0, 0.25, 0.5, 0.78, 1]  // y for x = 0,.25,.5,.78,1 (y[0]=0 → deep blacks)
        var clarity: Float = 0
        var grain: Float = 0
        var mono = false
        var blueDarken: Float = 0           // <1 darkens skies before mono (Acros yellow-filter)
        var bloom: Float = 0                // halation glow intensity (night looks)
        // Saturation CONTRAST, baked into the cube: pushes saturation away from
        // `satPivot` — muting already-dull colours while making vivid ones POP.
        // 1 = off. This is how Eterna keeps a muted green ambient while its neons
        // stay punchy: a flat global desaturation can't separate the two.
        var satContrast: Float = 1
        var satPivot: Float = 0.4
    }

    // MARK: Colour looks — recipe-driven pipeline

    /// `applyGrain` is false for the live preview — grain is baked into the captured
    /// photo only, so the preview stays clean (a static grain overlay "swims").
    static func colored(_ ci: CIImage, look: CameraLook, applyGrain: Bool = true) -> CIImage {
        if look == .original { return ci }
        let r = recipes[look] ?? Recipe()
        var x = ci
        // 1) White balance first (grade on corrected neutrals). Skip for B&W.
        if !r.mono { x = temperature(x, from: 6500, to: r.wbTo, tint: r.wbTint) }
        // 2) Acros: darken the blue channel (orange/yellow-filter sky) before mono.
        if r.blueDarken > 0 {
            let f = CIFilter.colorPolynomial(); f.inputImage = x
            f.blueCoefficients = CIVector(x: 0, y: CGFloat(r.blueDarken), z: 0, w: 0)
            x = f.outputImage ?? x
        }
        // 3) Per-hue signature (colour) or monochrome conversion.
        if r.mono {
            let m = CIFilter.photoEffectMono(); m.inputImage = x
            x = m.outputImage ?? x
        } else if cubes[look] != nil {
            x = applyCube(x, data: cubes[look]!)
        }
        // 4) Global sat/contrast — gentle; character comes from the cube + split.
        x = controls(x, sat: r.mono ? 0 : r.sat, con: r.con)
        // 5) Complementary split-tone — the cinematic heart.
        x = splitTone(x, shadow: r.shadow, highlight: r.highlight, strength: r.split)
        // 6) Halation bloom (night) — after the split so the glow inherits the grade.
        if r.bloom > 0 { x = bloom(x, intensity: r.bloom) }
        // 7) Tone curve LAST — re-anchors true black after the shadow tint.
        x = curve(x, [p(0, r.curveY[0]), p(0.25, r.curveY[1]), p(0.5, r.curveY[2]),
                      p(0.78, r.curveY[3]), p(1, r.curveY[4])])
        // 8) Clarity + grain.
        return finish(x, clarity: r.clarity, grain: r.grain, on: applyGrain)
    }

    /// The full look set. Numbers are grounded in real film colour-shift data and
    /// cinematic complementary-grading theory (researched), then tuned by eye.
    private static let recipes: [CameraLook: Recipe] = {
        var d: [CameraLook: Recipe] = [:]

        // ---- SUNNY · warm — reds→ORANGE, soft, olive greens; teal/amber split ----
        d[.portra] = Recipe(
            wbTo: 6600, wbTint: 0,                                  // near-neutral — no global orange cast
            // Skin was running YELLOW (owner, 2026-07): the reds→orange push bled
            // up into skin (~25°→33°). Reds still warm to orange, but the push is
            // gentler and the skin band pulls back toward red, so skin lands ~26–28°.
            bands: [Band(lo: 0, hi: 18, rot: 5, sat: 1.05),        // reds → orange, softer push
                    Band(lo: 18, hi: 42, rot: -3, sat: 1.03),      // SKIN — hold at red-orange, not yellow
                    Band(lo: 42, hi: 70, rot: 1, sat: 1.20),       // YELLOWS punchy
                    Band(lo: 80, hi: 160, rot: -9, sat: 0.86),     // greens → muted olive (Portra tell)
                    Band(lo: 165, hi: 200, rot: 3, sat: 0.88),     // cyans muted
                    Band(lo: 200, hi: 250, rot: -6, sat: 0.85)],   // skies soft, not punchy
            shadow: SIMD3(-0.03, 0.012, 0.05), highlight: SIMD3(0.018, 0.008, -0.024), split: 0.7,
            sat: 0.96, con: 0.99, curveY: [0, 0.20, 0.52, 0.82, 0.96], clarity: 0.15, grain: 0.17)

        // ---- SUNNY · airy-white — crimson reds, Fuji emerald greens, punchy ----
        // Skin-rebalanced (owner, 2026-07: faces came out red vs a Ricoh GR
        // reference). Skin lives at ~15–40°: that band now drifts slightly GOLD
        // (+3°) and desaturates a touch, the crimson push is kept for true reds
        // only (and halved), highlights tint amber-neutral instead of red, and the
        // global sat boost is mostly moved out of the way of skin. Landscape
        // character (emerald greens, teal-leaning skies) is untouched.
        d[.superia] = Recipe(
            wbTo: 6360, wbTint: 4,
            // Skin hue is fine (~25–27°); the "too red" was rising SATURATION
            // (owner, 2026-07) — the crimson reds + punch bled saturation into skin.
            // Skin desaturated a touch here; the emerald greens / teal skies keep it.
            bands: [Band(lo: 0, hi: 20, rot: -5, sat: 0.98, val: 0.97), Band(lo: 20, hi: 42, rot: 3, sat: 0.82),
                    Band(lo: 42, hi: 70, rot: 5, sat: 0.95), Band(lo: 80, hi: 160, rot: 8, sat: 1.22),
                    Band(lo: 160, hi: 195, rot: 2, sat: 1.12), Band(lo: 195, hi: 250, rot: -7, sat: 1.15)],
            shadow: SIMD3(-0.035, 0.025, 0.04), highlight: SIMD3(0.018, 0.014, 0.0), split: 0.7,
            // Softer contrast: gentle near-linear toe (light shadows keep detail), true
            // black only at the very bottom; lower contrast.
            sat: 1.0, con: 1.03, curveY: [0, 0.245, 0.50, 0.78, 0.98], clarity: 0.15, grain: 0)

        // ---- VIVID — bold clean colour, deep skies, electric greens ----
        d[.ektar] = Recipe(
            wbTo: 6540, wbTint: 1,
            // Skin ran intense/ruddy (owner, 2026-07) — hue pushed toward yellow AND
            // saturation climbed. Skin band now holds near red-orange (rot −1) and
            // desaturates; the bold sat stays in greens/blues/clarity, not on faces.
            bands: [Band(lo: 0, hi: 22, rot: 3, sat: 0.98), Band(lo: 22, hi: 45, rot: -2, sat: 0.78),
                    Band(lo: 45, hi: 70, rot: 0, sat: 1.10), Band(lo: 80, hi: 160, rot: -8, sat: 1.12),
                    Band(lo: 160, hi: 195, rot: 0, sat: 1.06), Band(lo: 195, hi: 255, rot: -5, sat: 1.18),
                    Band(lo: 255, hi: 338, rot: -3, sat: 0.92)],
            shadow: SIMD3(-0.02, 0.005, 0.04), highlight: SIMD3(0.030, 0.012, -0.028), split: 0.8,
            sat: 1.07, con: 1.04, curveY: [0, 0.225, 0.51, 0.83, 0.99], clarity: 0.25, grain: 0.12)

        // ---- OVERCAST · cold-airy — cyan-greens, pastel, cool/clean split ----
        d[.pro400h] = Recipe(
            wbTo: 6900, wbTint: 6,
            // Skin stays pastel-desaturated but no longer drifts toward red (rot ≈ 0).
            bands: [Band(lo: 80, hi: 165, rot: 15, sat: 0.80), Band(lo: 165, hi: 200, rot: -4, sat: 0.95),
                    Band(lo: 200, hi: 250, rot: 4, sat: 0.88), Band(lo: 0, hi: 20, rot: -1, sat: 0.78),
                    Band(lo: 20, hi: 45, rot: -1, sat: 0.82)],
            shadow: SIMD3(-0.03, 0.03, 0.045), highlight: SIMD3(-0.012, 0, 0.008), split: 0.7,
            sat: 0.85, con: 0.95, curveY: [0, 0.23, 0.49, 0.80, 0.94], clarity: 0.13, grain: 0.14)

        // ---- OVERCAST · warm-airy — soft warm-neutral, creamy ----
        d[.astia] = Recipe(
            wbTo: 6750, wbTint: 4,
            bands: [Band(lo: 0, hi: 25, rot: 5, sat: 0.92), Band(lo: 25, hi: 45, rot: 1, sat: 0.96),
                    Band(lo: 38, hi: 70, rot: 0, sat: 0.95), Band(lo: 80, hi: 160, rot: -7, sat: 0.85, val: 0.97),
                    Band(lo: 195, hi: 250, rot: 0, sat: 0.90)],
            shadow: SIMD3(-0.022, 0.012, 0.03), highlight: SIMD3(0.03, 0.012, -0.022), split: 0.55,
            sat: 0.86, con: 0.95, curveY: [0, 0.23, 0.50, 0.80, 0.94], clarity: 0.13, grain: 0.14)

        // ---- NIGHT · red — teal shadows / red-orange highlights + halation ----
        d[.cinestill] = Recipe(
            wbTo: 6800, wbTint: 3,
            bands: [Band(lo: 0, hi: 30, rot: 1, sat: 1.07), Band(lo: 30, hi: 50, rot: 0, sat: 1.04),
                    Band(lo: 80, hi: 175, rot: 10, sat: 0.90), Band(lo: 195, hi: 255, rot: 0, sat: 1.0)],
            shadow: SIMD3(-0.04, 0.02, 0.05), highlight: SIMD3(0.05, 0, -0.04), split: 0.9,
            sat: 0.97, con: 1.02, curveY: [0, 0.22, 0.50, 0.79, 0.95], clarity: 0.15, grain: 0.20, bloom: 0.18)

        // ---- NIGHT · green (Matrix grade) — phosphor-green cast, punchy, glowing ----
        // Reworked 2026-07-14 (owner: "should be like the Matrix — greenish night
        // vision, saturated" — the old version read yellowish + desaturated).
        // Three causes fixed: the highlight tint was green MINUS blue (green−blue
        // = yellow); everything was desaturated (0.55–0.9 bands, 0.92 global) so
        // no colour survived to read green; and the WB green tint was too weak to
        // overpower neon scenes. Now: cold base + a strong green tint, green in
        // BOTH split ends with blue never negative (emerald, not yellow), greens
        // pushed hard, competing hues rotated toward green or crushed, saturation
        // UP, deeper toe, more bloom (phosphor glow).
        d[.eterna] = Recipe(
            wbTo: 7200, wbTint: 30,                                    // cool + a moderate green cast
            bands: [Band(lo: 80, hi: 170, rot: 4, sat: 1.20),          // greens → lime
                    Band(lo: 170, hi: 200, rot: -8, sat: 1.05),        // cyans → green-teal
                    Band(lo: 200, hi: 260, rot: -12, sat: 1.02),       // blues → teal, keep the punch
                    Band(lo: 0, hi: 30, rot: 4, sat: 1.05),            // reds: neon punch comes from satContrast,
                    Band(lo: 30, hi: 65, rot: 6, sat: 1.05),           // amber: keep the per-hue boost gentle so
                    Band(lo: 285, hi: 350, rot: -8, sat: 1.05)],       // magenta: skin/lit faces don't run hot
            // Green from the shadow split (mood down low); highlights near-neutral
            // so bright neon isn't tinted. Blue never below green (→ yellow).
            shadow: SIMD3(-0.05, 0.055, 0.006), highlight: SIMD3(-0.01, 0.012, 0.004), split: 0.9,
            // The Matrix split: MUTE the dull ambient, POP the vivid neon — done by
            // satContrast (below), not a flat desaturation (which kills the neon
            // too). Dark, contrasty, crisp; the shadow split greens the ambient.
            sat: 0.98, con: 1.14, curveY: [0, 0.15, 0.44, 0.80, 0.97], clarity: 0.30, grain: 0.16, bloom: 0.16,
            satContrast: 1.5, satPivot: 0.34)

        // ---- B&W · soft — gritty grain, airy skies, faint warm tone ----
        d[.trix] = Recipe(
            shadow: SIMD3(0.012, 0.004, -0.012), highlight: SIMD3(-0.008, 0, 0.012), split: 0.5,
            con: 1.02, curveY: [0, 0.235, 0.50, 0.78, 0.94], clarity: 0.2, grain: 0.30, mono: true)

        // ---- B&W · contrasted — crisp, dense dramatic skies, faint cool tone ----
        d[.acros] = Recipe(
            shadow: SIMD3(-0.012, -0.004, 0.016), highlight: SIMD3(0.012, 0.004, -0.008), split: 0.5,
            con: 1.09, curveY: [0, 0.185, 0.51, 0.83, 0.985], clarity: 0.34, grain: 0.10,
            mono: true, blueDarken: 0.88)

        return d
    }()

    /// Per-look colour cubes, built once from each recipe's hue bands.
    private static let cubes: [CameraLook: Data] = {
        var d: [CameraLook: Data] = [:]
        for look in CameraLook.allCases {
            guard let r = recipes[look], !r.mono, !r.bands.isEmpty else { continue }
            d[look] = makeCube { bandMap($0, r.bands, satContrast: r.satContrast, satPivot: r.satPivot) }
        }
        return d
    }()

    /// Final touches: a little clarity (crisp edges) and real film grain.
    /// Grain is skipped when `applyGrain` is false (live preview).
    private static func finish(_ ci: CIImage, clarity c: Float, grain g: Float, on applyGrain: Bool = true) -> CIImage {
        var x = ci
        if c > 0 {
            let f = CIFilter.unsharpMask(); f.inputImage = x; f.radius = 2.4; f.intensity = c
            x = f.outputImage ?? x
        }
        if g > 0 && applyGrain { x = grain(x, g) }
        return x
    }

    /// Film grain: the finite noise tile scaled to cover the frame, overlay-blended.
    /// Kept STRICTLY bounded — both an infinite `randomGenerator` and a degenerate
    /// `affineTile` (infinite extent) crash the editor's off-screen `createCGImage`
    /// render at full resolution. The tile is baked large (below) so this modest
    /// upscale stays fine, not chunky.
    private static func grain(_ ci: CIImage, _ amount: Float) -> CIImage {
        let e = ci.extent
        let t = grainTile.extent
        let s = max(e.width / t.width, e.height / t.height)
        let n = grainTile
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
            .cropped(to: e)
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))])
        let b = CIFilter.overlayBlendMode(); b.backgroundImage = ci; b.inputImage = n
        return (b.outputImage ?? ci).cropped(to: e)
    }

    /// A finite monochrome noise bitmap, rendered ONCE. Using a real bitmap (not a
    /// live procedural generator) keeps every render's memory bounded.
    private static let grainTile: CIImage = {
        let dim: CGFloat = 2048   // large enough that covering a full-res photo barely upscales → fine grain
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let raw = (CIFilter.randomGenerator().outputImage ?? CIImage())
            .cropped(to: CGRect(x: 0, y: 0, width: dim, height: dim))
        let mono = CIFilter.colorControls(); mono.inputImage = raw
        mono.saturation = 0; mono.brightness = -0.05; mono.contrast = 2.2
        let out = mono.outputImage ?? raw
        if let cg = ctx.createCGImage(out, from: CGRect(x: 0, y: 0, width: dim, height: dim)) {
            return CIImage(cgImage: cg)
        }
        return out
    }()

    /// Soft highlight glow — halation around lights. Bloom enlarges the extent, so
    /// crop back to the input's frame (an enlarged extent crashes off-screen render).
    private static func bloom(_ ci: CIImage, intensity: Float) -> CIImage {
        let f = CIFilter.bloom(); f.inputImage = ci; f.radius = 6; f.intensity = intensity
        return (f.outputImage ?? ci).cropped(to: ci.extent)
    }

    // MARK: Building blocks

    private static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func controls(_ ci: CIImage, sat: Float, con: Float, bri: Float = 0) -> CIImage {
        let f = CIFilter.colorControls(); f.inputImage = ci
        f.saturation = sat; f.contrast = con; f.brightness = bri
        return f.outputImage ?? ci
    }

    private static func curve(_ ci: CIImage, _ pts: [CGPoint]) -> CIImage {
        let f = CIFilter.toneCurve(); f.inputImage = ci
        f.point0 = pts[0]; f.point1 = pts[1]; f.point2 = pts[2]; f.point3 = pts[3]; f.point4 = pts[4]
        return f.outputImage ?? ci
    }

    /// White balance shift. `tint` on the green↔magenta axis (negative = green).
    private static func temperature(_ ci: CIImage, from: CGFloat, to: CGFloat, tint: CGFloat = 0) -> CIImage {
        guard to != from || tint != 0 else { return ci }
        let f = CIFilter.temperatureAndTint(); f.inputImage = ci
        f.neutral = CIVector(x: from, y: 0); f.targetNeutral = CIVector(x: to, y: tint)
        return f.outputImage ?? ci
    }

    /// Complementary split-tone via a per-channel cubic (CIColorPolynomial):
    /// out = c0 + c1·s + c2·s² + c3·s³. The SHADOW tint rides the s² term (peaks in
    /// the low-mids) and the HIGHLIGHT tint the s³ term (acts near s=1), so the two
    /// own opposite ends of the luminance range and can never average to grey mud.
    /// c0 = 0 on every channel ALWAYS → out(0)=0 → true blacks survive every grade.
    private static func splitTone(_ ci: CIImage, shadow: SIMD3<Float>, highlight: SIMD3<Float>, strength s: Float) -> CIImage {
        guard s > 0 else { return ci }
        let f = CIFilter.colorPolynomial(); f.inputImage = ci
        func co(_ shadowT: Float, _ highT: Float) -> CIVector {
            let ts = shadowT * s, th = highT * s
            let c2 = 4 * ts
            let c3 = th - c2
            let c1 = 1 - c2 / 3
            return CIVector(x: 0, y: CGFloat(c1), z: CGFloat(c2), w: CGFloat(c3))
        }
        f.redCoefficients   = co(shadow.x, highlight.x)
        f.greenCoefficients = co(shadow.y, highlight.y)
        f.blueCoefficients  = co(shadow.z, highlight.z)
        return f.outputImage ?? ci
    }

    // MARK: Per-hue colour cubes (LUTs)

    private static let cubeSize = 24

    private static func applyCube(_ ci: CIImage, data: Data) -> CIImage {
        // Plain CIColorCube (no colour space): rock-solid with createCGImage. The
        // colour-space variant crashed when rendered off-screen via createCGImage.
        let f = CIFilter.colorCube()
        f.cubeDimension = Float(cubeSize)
        f.cubeData = data
        f.inputImage = ci
        return f.outputImage ?? ci
    }

    private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Feathered weight of hue `h` in band `b` (hue-circle aware). 1 deep inside
    /// the band, easing to 0 across ~10° outside its edges, so neighbouring bands
    /// BLEND instead of snapping. Hard band edges were visible on faces: skin spans
    /// roughly 15–40°, so a face straddled two bands with different treatments and
    /// came out blotchy where the boundary cut across it.
    private static func bandWeight(_ h: Float, _ b: Band) -> Float {
        let f: Float = min(10, (b.hi - b.lo) / 2)
        for hh in [h, h - 360, h + 360] where hh >= b.lo - f && hh <= b.hi + f {
            return min(smoothstep(b.lo - f, b.lo + f, hh),
                       1 - smoothstep(b.hi - f, b.hi + f, hh))
        }
        return 0
    }

    /// Apply a look's hue bands to one colour: rotate hue + scale sat/value by the
    /// feather-weighted sum of every band covering this hue. Greens are kept from
    /// crossing into cyan (≤178°).
    private static func bandMap(_ rgb: SIMD3<Float>, _ bands: [Band],
                                satContrast: Float = 1, satPivot: Float = 0.4) -> SIMD3<Float> {
        var hsv = rgb2hsv(rgb)
        let h = hsv.x
        var rot: Float = 0, satM: Float = 1, valM: Float = 1
        for b in bands {
            let w = bandWeight(h, b)
            guard w > 0 else { continue }
            rot += w * b.rot
            satM += w * (b.sat - 1)
            valM += w * (b.val - 1)
        }
        var nh = h + rot
        if rot > 0 && h < 180 && nh > 178 { nh = 178 }   // don't tip greens into cyan
        hsv.x = nh
        var s = hsv.y * max(satM, 0)
        // Saturation contrast: expand away from the pivot so dull colours go duller
        // (muted green ambient) and vivid ones go more vivid (punchy neon).
        if satContrast != 1 { s = satPivot + (s - satPivot) * satContrast }
        hsv.y = min(max(s, 0), 1)
        hsv.z = hsv.z * max(valM, 0)
        if hsv.x < 0 { hsv.x += 360 }
        if hsv.x >= 360 { hsv.x -= 360 }
        return hsv2rgb(hsv)
    }

    /// Builds CIColorCube data by mapping every grid colour through `map` (sRGB).
    private static func makeCube(_ map: (SIMD3<Float>) -> SIMD3<Float>) -> Data {
        let n = cubeSize
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let rgb = SIMD3<Float>(Float(r) / Float(n - 1),
                                           Float(g) / Float(n - 1),
                                           Float(b) / Float(n - 1))
                    let out = map(rgb)
                    cube[i + 0] = min(max(out.x, 0), 1)
                    cube[i + 1] = min(max(out.y, 0), 1)
                    cube[i + 2] = min(max(out.z, 0), 1)
                    cube[i + 3] = 1
                    i += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func rgb2hsv(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let r = c.x, g = c.y, b = c.z
        let mx = max(r, max(g, b)), mn = min(r, min(g, b))
        let d = mx - mn
        var h: Float = 0
        if d > 1e-6 {
            if mx == r { h = (g - b) / d }
            else if mx == g { h = 2 + (b - r) / d }
            else { h = 4 + (r - g) / d }
            h *= 60; if h < 0 { h += 360 }
        }
        let s = mx <= 1e-6 ? 0 : d / mx
        return SIMD3(h, s, mx)
    }

    private static func hsv2rgb(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let h = c.x, s = c.y, v = c.z
        if s <= 1e-6 { return SIMD3(v, v, v) }
        let hh = h.truncatingRemainder(dividingBy: 360) / 60
        let idx = Int(floor(hh))
        let f = hh - Float(idx)
        let pp = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch idx % 6 {
        case 0: return SIMD3(v, t, pp)
        case 1: return SIMD3(q, v, pp)
        case 2: return SIMD3(pp, v, t)
        case 3: return SIMD3(pp, q, v)
        case 4: return SIMD3(t, pp, v)
        default: return SIMD3(v, pp, q)
        }
    }

    // MARK: Keystone

    static func keystoned(_ ci: CIImage, strength: Double) -> CIImage {
        let e = ci.extent
        guard e.width > 0, e.height > 0 else { return ci }
        let k = min(0.6, abs(strength) * 0.6) * e.width
        let f = CIFilter.perspectiveTransform()
        f.inputImage = ci
        if strength > 0 {
            f.topLeft = CGPoint(x: e.minX - k, y: e.maxY)
            f.topRight = CGPoint(x: e.maxX + k, y: e.maxY)
            f.bottomLeft = CGPoint(x: e.minX, y: e.minY)
            f.bottomRight = CGPoint(x: e.maxX, y: e.minY)
        } else {
            f.topLeft = CGPoint(x: e.minX, y: e.maxY)
            f.topRight = CGPoint(x: e.maxX, y: e.maxY)
            f.bottomLeft = CGPoint(x: e.minX - k, y: e.minY)
            f.bottomRight = CGPoint(x: e.maxX + k, y: e.minY)
        }
        var out = f.outputImage ?? ci

        // Straightening verticals widens one end, which leaves the subject looking
        // short and squashed. Counter it with a vertical stretch (about the centre)
        // that grows with the tilt — keeps the object's proportions natural.
        let v = 1.0 + abs(strength) * 0.5
        let stretch = CGAffineTransform(translationX: 0, y: e.midY)
            .scaledBy(x: 1, y: v)
            .translatedBy(x: 0, y: -e.midY)
        out = out.transformed(by: stretch)

        // Crop back to the original frame, centred.
        let cw = e.width * 0.99, ch = e.height * 0.99
        return out.cropped(to: CGRect(x: e.midX - cw / 2, y: e.midY - ch / 2, width: cw, height: ch))
    }
}
