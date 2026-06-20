import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Cinematic colour looks. White-balance-led grades (the lever that matters most
/// for a filmic result), plus genuine *per-hue* control via a colour cube (LUT)
/// so greens can go muted-teal and the iPhone's over-saturated reds can be
/// reined in — the way Fuji film sims and Ricoh GR recipes actually behave.
enum CameraLook: String, CaseIterable, Identifiable {
    case original  = "Original"
    case portra    = "Portra 400"      // warm, soft, peachy reds, blacks kept
    case gold      = "Gold 200"        // gently golden, nostalgic
    case superia   = "Superia 400"     // sunny, warm, pastel — Fuji summer (no grain)
    case astia     = "Astia 100"       // airy cinematic: high-key whites, dark greens, deep reds
    case ektar     = "Ektar 100"       // clean, a little vivid
    case pro400h   = "Pro 400H"        // Fuji: soft, green-leaning, creamy
    case cinestill = "CineStill 800T"  // tungsten: cool, teal shadows, soft halation
    case eterna    = "Eterna 500"      // night: cold WB, pushed greens, deep blacks, neon glow
    case trix      = "Tri-X 400"       // soft-contrast black & white
    var id: String { rawValue }
}

enum CameraProcessing {
    static func apply(to input: CIImage, keystone: Double, look: CameraLook, grain: Bool = true) -> CIImage {
        var img = input
        if abs(keystone) > 0.01 { img = keystoned(img, strength: keystone) }
        img = colored(img, look: look, applyGrain: grain)
        return img
    }

    // MARK: Colour looks

    /// `applyGrain` is false for the live preview — grain is baked into the
    /// captured photo only, so the preview stays clean (a static grain overlay
    /// "swims" over moving content, which reads as the grain moving).
    static func colored(_ ci: CIImage, look: CameraLook, applyGrain: Bool = true) -> CIImage {
        switch look {
        case .original:
            return ci

        // The Fuji philosophy: restraint. Character comes from TONE (deep blacks +
        // smooth highlight rolloff), gentle hue moves and a subtle cool-shadow /
        // warm-highlight split — NOT pumped saturation. Saturation stays ~neutral.

        case .portra:                                  // Portra 400 — warm, soft, natural
            var x = temperature(ci, from: 6500, to: 6380)
            x = applyCube(x, data: portraCube)
            x = controls(x, sat: 0.99, con: 0.99)
            x = splitTone(x, strength: 0.6)            // gentle cool shadows / warm highlights
            // deep blacks, smooth highlight rolloff (highlights compress, don't clip)
            let y = curve(x, [p(0,0.0), p(0.25,0.25), p(0.5,0.5), p(0.78,0.78), p(1,0.94)])
            return finish(y, clarity: 0.15, grain: 0.17, on: applyGrain)

        case .gold:                                    // Gold 200 — gently warm, nostalgic
            var x = temperature(ci, from: 6500, to: 6360)
            x = applyCube(x, data: goldCube)
            x = controls(x, sat: 1.02, con: 1.0)
            let y = curve(x, [p(0,0.0), p(0.25,0.245), p(0.5,0.5), p(0.78,0.79), p(1,0.95)])
            return finish(y, clarity: 0.15, grain: 0.17, on: applyGrain)

        case .superia:                                 // Superia 400 — sunny, warm, pastel; no grain
            var x = temperature(ci, from: 6500, to: 6700)            // warm, sunny
            x = applyCube(x, data: superiaCube)
            x = controls(x, sat: 1.03, con: 0.98)
            x = vibrance(x, 0.10)
            x = splitTone(x, strength: 0.4)                          // warm highlights, faint teal shadows
            // airy: a whisper of black lift + bright mids + soft highlight rolloff
            let y = curve(x, [p(0,0.012), p(0.25,0.27), p(0.5,0.52), p(0.78,0.8), p(1,0.96)])
            return finish(y, clarity: 0.12, grain: 0, on: applyGrain) // clean, grain-free

        case .astia:                                   // Astia 100 — airy cinematic: white, dark greens, deep reds
            var x = temperature(ci, from: 6500, to: 6600)        // clean, faintly cool whites
            x = controls(x, sat: 0.90, con: 0.95)                // muted, low-contrast (cinematic)
            x = applyCube(x, data: astiaCube)                    // reds back to rich/deep, greens pushed dark
            x = splitTone(x, strength: 0.3)                      // a whisper of warmth up top
            // airy: lifted milky blacks, bright soft highlights
            let y = curve(x, [p(0,0.04), p(0.25,0.29), p(0.5,0.53), p(0.78,0.82), p(1,0.97)])
            return finish(y, clarity: 0.10, grain: 0, on: applyGrain) // clean & airy, grain-free

        case .ektar:                                   // Ektar 100 — clean, lightly vivid (the punchy one)
            var x = temperature(ci, from: 6500, to: 6560)
            x = applyCube(x, data: ektarCube)
            x = controls(x, sat: 1.06, con: 1.03)
            let y = curve(x, [p(0,0.0), p(0.25,0.24), p(0.5,0.5), p(0.78,0.8), p(1,0.99)])
            return finish(y, clarity: 0.25, grain: 0.13, on: applyGrain)

        case .pro400h:                                 // Fuji Pro 400H — soft, green-leaning, creamy
            var x = temperature(ci, from: 6500, to: 6650, tint: -6)   // gently cool + green
            x = applyCube(x, data: pro400hCube)
            x = controls(x, sat: 0.97, con: 0.97)                     // soft, refined
            x = splitTone(x, strength: 0.6)                           // gentle, green-leaning (no purple)
            let y = curve(x, [p(0,0.0), p(0.25,0.255), p(0.5,0.51), p(0.78,0.79), p(1,0.94)])
            return finish(y, clarity: 0.15, grain: 0.17, on: applyGrain)

        case .cinestill:                               // CineStill 800T — moody tungsten, teal shadows
            var x = temperature(ci, from: 6500, to: 6800)
            x = applyCube(x, data: cinestillCube)
            x = controls(x, sat: 0.97, con: 1.02)
            x = splitTone(x, strength: 0.9)                   // teal shadows / warm highlights (no purple)
            x = bloom(x)                                      // subtle halation glow
            let y = curve(x, [p(0,0.0), p(0.25,0.23), p(0.5,0.5), p(0.78,0.79), p(1,0.95)])
            return finish(y, clarity: 0.15, grain: 0.20, on: applyGrain)

        case .eterna:                                  // Eterna 500 — night: cold, green-pushed, cinematic
            var x = temperature(ci, from: 6500, to: 7000, tint: -12)  // cold white balance + green
            x = applyCube(x, data: eternaCube)
            x = controls(x, sat: 1.04, con: 1.05)                     // a little punch
            x = splitTone(x, strength: 1.0)                           // teal shadows / warm city-light highlights
            x = bloom(x)                                              // neon halation
            // deep, slightly crushed blacks; protect the warm highlights
            let y = curve(x, [p(0,0.0), p(0.25,0.21), p(0.5,0.49), p(0.78,0.78), p(1,0.95)])
            return finish(y, clarity: 0.18, grain: 0.14, on: applyGrain)

        case .trix:                                    // Tri-X 400 — soft black & white
            let m = CIFilter.photoEffectMono(); m.inputImage = ci
            let base = controls(m.outputImage ?? ci, sat: 1, con: 1.02)
            let y = curve(base, [p(0,0.0), p(0.25,0.23), p(0.5,0.5), p(0.78,0.79), p(1,0.95)])
            return finish(y, clarity: 0.2, grain: 0.28, on: applyGrain)
        }
    }

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

    /// Film grain: the finite noise tile repeated at 1:1 (no upscaling) so the
    /// grain stays fine and photographic at any resolution, then overlay-blended.
    private static func grain(_ ci: CIImage, _ amount: Float) -> CIImage {
        let e = ci.extent
        let tile = CIFilter.affineTile()
        tile.inputImage = grainTile
        tile.transform = .identity                        // repeat 1:1 — fine grain
        let n = (tile.outputImage ?? grainTile)
            .cropped(to: e)
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))])
        let b = CIFilter.overlayBlendMode(); b.backgroundImage = ci; b.inputImage = n
        return (b.outputImage ?? ci).cropped(to: e)
    }

    /// A finite monochrome noise bitmap, rendered ONCE. Using a real bitmap (not a
    /// live procedural generator) keeps every render's memory bounded — the
    /// infinite generator was spiking memory and getting the app jetsam-killed.
    private static let grainTile: CIImage = {
        let dim: CGFloat = 1024
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

    /// Soft highlight glow — CineStill's halation, kept subtle. Bloom enlarges
    /// the extent, so crop back to the input's frame.
    private static func bloom(_ ci: CIImage) -> CIImage {
        let f = CIFilter.bloom(); f.inputImage = ci; f.radius = 6; f.intensity = 0.18
        return (f.outputImage ?? ci).cropped(to: ci.extent)
    }

    // MARK: Building blocks

    private static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func controls(_ ci: CIImage, sat: Float, con: Float, bri: Float = 0) -> CIImage {
        let f = CIFilter.colorControls(); f.inputImage = ci
        f.saturation = sat; f.contrast = con; f.brightness = bri
        return f.outputImage ?? ci
    }

    private static func vibrance(_ ci: CIImage, _ amount: Float) -> CIImage {
        let f = CIFilter.vibrance(); f.inputImage = ci; f.amount = amount
        return f.outputImage ?? ci
    }

    private static func curve(_ ci: CIImage, _ pts: [CGPoint]) -> CIImage {
        let f = CIFilter.toneCurve(); f.inputImage = ci
        f.point0 = pts[0]; f.point1 = pts[1]; f.point2 = pts[2]; f.point3 = pts[3]; f.point4 = pts[4]
        return f.outputImage ?? ci
    }

    /// White balance shift. `tint` on the green↔magenta axis (negative = green).
    private static func temperature(_ ci: CIImage, from: CGFloat, to: CGFloat, tint: CGFloat = 0) -> CIImage {
        let f = CIFilter.temperatureAndTint(); f.inputImage = ci
        f.neutral = CIVector(x: from, y: 0); f.targetNeutral = CIVector(x: to, y: tint)
        return f.outputImage ?? ci
    }

    /// Teal in the shadows, warmth in the highlights — the cinematic balance,
    /// scaled by `strength` (≈1 gentle, ≈2 pronounced). Green is lifted in the
    /// shadows alongside blue so they read TEAL/cyan, not blue-magenta — lifting
    /// blue alone (with red still present) is what made shadows go purple.
    private static func splitTone(_ ci: CIImage, strength s: Float) -> CIImage {
        let f = CIFilter.colorPolynomial(); f.inputImage = ci
        f.redCoefficients   = CIVector(x: CGFloat(-0.010 * s), y: CGFloat(1 + 0.030 * s), z: 0, w: 0)
        f.greenCoefficients = CIVector(x: CGFloat(0.004 * s), y: 1, z: 0, w: 0)
        f.blueCoefficients  = CIVector(x: CGFloat(0.012 * s), y: CGFloat(1 - 0.012 * s), z: CGFloat(-0.010 * s), w: 0)
        return f.outputImage ?? ci
    }

    // MARK: Per-hue colour cubes (LUTs)

    private static let cubeSize = 24

    private static func applyCube(_ ci: CIImage, data: Data) -> CIImage {
        // Plain CIColorCube (no colour space): rock-solid with createCGImage. The
        // colour-space variant crashed when rendered off-screen via createCGImage
        // (the live camera renders via a Metal drawable, which didn't hit it).
        let f = CIFilter.colorCube()
        f.cubeDimension = Float(cubeSize)
        f.cubeData = data
        f.inputImage = ci
        return f.outputImage ?? ci
    }

    /// Builds CIColorCube data by mapping every grid colour through `map`
    /// (applied in sRGB). Built once per look and reused every frame.
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

    // All cubes are deliberately gentle — the Fuji character is subtle.

    // Portra: a faint red→orange (peachy), greens barely eased.
    private static let portraCube = makeCube { rgb in
        var hsv = rgb2hsv(rgb)
        let h = hsv.x
        if h <= 20 { hsv.x = h + 5 }                                 // reds → orange (faint)
        else if h > 85 && h < 165 { hsv.y *= 0.95 }                 // greens barely eased
        return hsv2rgb(hsv)
    }

    // Gold: greens drift slightly to gold, yellows a touch fuller.
    private static let goldCube = makeCube { rgb in
        var hsv = rgb2hsv(rgb)
        let h = hsv.x
        if h > 75 && h < 160 { hsv.x = h - 6; hsv.y *= 0.95 }         // greens → gold (subtle)
        else if h >= 38 && h <= 70 { hsv.y = min(hsv.y * 1.04, 1) }  // yellows
        return hsv2rgb(hsv)
    }

    // Superia: Fuji summer — greens drift to fresher yellow-green, yellows fuller
    // (sun), teals/cyans kept clean, reds eased toward orange. Warm but not garish.
    private static let superiaCube = makeCube { rgb in
        var hsv = rgb2hsv(rgb)
        let h = hsv.x
        if h > 80 && h < 160 { hsv.x = h - 8; hsv.y = min(hsv.y * 1.04, 1) }      // greens → yellow-green
        else if h >= 38 && h <= 65 { hsv.y = min(hsv.y * 1.05, 1) }               // yellows fuller (sun)
        else if h > 165 && h < 205 { hsv.y = min(hsv.y * 1.03, 1) }               // teal / cyan kept clean
        else if h <= 22 { hsv.x = h + 4; hsv.y *= 0.98 }                          // reds → faint orange
        return hsv2rgb(hsv)
    }

    // Astia: airy cinematic — reds kept rich & deep, greens darkened and muted into
    // cinematic forest-green, the rest gently desaturated (after a global desat).
    private static let astiaCube = makeCube { rgb in
        var hsv = rgb2hsv(rgb)
        let h = hsv.x
        if h <= 25 || h > 335 { hsv.y = min(hsv.y * 1.22, 1); hsv.z *= 0.97 }       // reds → deep & rich
        else if h > 80 && h < 165 { hsv.z *= 0.86; hsv.y = min(hsv.y * 1.05, 1) }   // greens → dark, still green
        else if h >= 38 && h <= 70 { hsv.y *= 0.90 }                               // yellows eased
        return hsv2rgb(hsv)
    }

    // Ektar: a light lift of the primaries — clean, not garish.
    private static let ektarCube = makeCube { rgb in
        var hsv = rgb2hsv(rgb)
        let h = hsv.x
        if h < 30 || h > 335 { hsv.y = min(hsv.y * 1.06, 1) }        // reds
        else if h > 195 && h < 260 { hsv.y = min(hsv.y * 1.05, 1) }  // blues
        else if h > 80 && h < 165 { hsv.y *= 0.98 }                  // greens
        return hsv2rgb(hsv)
    }

    // Pro 400H: greens nudged subtly toward cyan and slightly muted — Fuji green.
    private static let pro400hCube = makeCube { rgb in
        var hsv = rgb2hsv(rgb)
        let h = hsv.x
        if h > 70 && h < 175 { hsv.x = min(h + 5, 180); hsv.y *= 0.96 }  // greens → cyan-green, eased
        else if h < 30 || h > 330 { hsv.y *= 0.95 }                     // reds eased
        return hsv2rgb(hsv)
    }

    // Eterna: night cinema — greens & cyans pushed and pulled toward teal; warm
    // city lights (reds/oranges) kept saturated so they pop against the cold green.
    private static let eternaCube = makeCube { rgb in
        var hsv = rgb2hsv(rgb)
        let h = hsv.x
        if h > 90 && h < 165 { hsv.x = min(h + 12, 175); hsv.y = min(hsv.y * 1.18, 1) }   // greens → teal, pushed
        else if h >= 165 && h < 200 { hsv.y = min(hsv.y * 1.15, 1) }                       // cyans pushed
        else if h <= 30 || h > 335 { hsv.y = min(hsv.y * 1.05, 1) }                        // warm lights kept
        return hsv2rgb(hsv)
    }

    // CineStill: greens drift to teal and mute (cool WB + split-tone do the rest).
    private static let cinestillCube = makeCube { rgb in
        var hsv = rgb2hsv(rgb)
        let h = hsv.x
        if h > 80 && h < 175 { hsv.x = min(h + 10, 178); hsv.y *= 0.90 }
        return hsv2rgb(hsv)
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

        // Crop back to the original frame, centred. The full sensor width fits with
        // no transparent edges, so no zoom-in is needed — nothing leaves the frame.
        let cw = e.width * 0.99, ch = e.height * 0.99
        return out.cropped(to: CGRect(x: e.midX - cw / 2, y: e.midY - ch / 2, width: cw, height: ch))
    }
}
