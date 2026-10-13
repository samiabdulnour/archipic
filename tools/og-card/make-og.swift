// Builds docs/og.png, the 1200×630 card that iMessage, Slack, LinkedIn and
// Hacker News show when someone pastes a link to archipic.app.
//
// Run from the repo root:
//   swift tools/og-card/make-og.swift [screenshot.png]
//
// It reads the current app icon from the asset catalog and one framed App Store
// screenshot (default: AppStoreScreenshots/Framed/02-archive.png), and draws them
// on the website's paper colour with the name and tagline. Plain AppKit, no
// dependencies, so it can be re-run whenever the icon or screenshots change.

import AppKit

let W = 1200, H = 630
let iconPath = "Archipic/Archipic/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let shotPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppStoreScreenshots/Framed/02-archive.png"
let outPath = "docs/og.png"

// Site colours (docs/style.css).
let paper = NSColor(srgbRed: 0xF1 / 255.0, green: 0xEE / 255.0, blue: 0xE8 / 255.0, alpha: 1)
let ink   = NSColor(srgbRed: 0x16 / 255.0, green: 0x14 / 255.0, blue: 0x0F / 255.0, alpha: 1)
let ink2  = NSColor(srgbRed: 0x3A / 255.0, green: 0x35 / 255.0, blue: 0x2B / 255.0, alpha: 1)
let ink3  = NSColor(srgbRed: 0x6E / 255.0, green: 0x66 / 255.0, blue: 0x57 / 255.0, alpha: 1)

func load(_ path: String) -> CGImage {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write("Can't read \(path). Run this from the repo root.\n".data(using: .utf8)!)
        exit(1)
    }
    return cg
}

let icon = load(iconPath)
let shot = load(shotPath)

// An exact 1200×630 bitmap (1 point = 1 pixel), drawn with a top-left origin so
// the numbers below read like a layout.
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let cg = gc.cgContext
cg.translateBy(x: 0, y: CGFloat(H))
cg.scaleBy(x: 1, y: -1)

func drawImage(_ image: CGImage, in rect: CGRect) {
    // CGContext draws images bottom-up; flip locally so they land upright.
    cg.saveGState()
    cg.translateBy(x: rect.minX, y: rect.maxY)
    cg.scaleBy(x: 1, y: -1)
    cg.interpolationQuality = .high
    cg.draw(image, in: CGRect(origin: .zero, size: rect.size))
    cg.restoreGState()
}

func drawText(_ s: String, font: NSFont, color: NSColor, at origin: CGPoint, width: CGFloat,
              lineHeight: CGFloat = 1.0, kern: CGFloat = 0) -> CGFloat {
    let para = NSMutableParagraphStyle()
    para.lineHeightMultiple = lineHeight
    let str = NSAttributedString(string: s, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: para, .kern: kern])
    let bounds = str.boundingRect(with: NSSize(width: width, height: 1000),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading])
    // AppKit text wants an unflipped context; flip just for this draw.
    cg.saveGState()
    cg.translateBy(x: origin.x, y: origin.y + bounds.height)
    cg.scaleBy(x: 1, y: -1)
    str.draw(with: NSRect(x: 0, y: 0, width: width, height: bounds.height),
             options: [.usesLineFragmentOrigin, .usesFontLeading])
    cg.restoreGState()
    return bounds.height
}

// Background.
paper.setFill()
cg.fill(CGRect(x: 0, y: 0, width: W, height: H))

// Right: the framed screenshot, cropped to the phone (below its headline) and
// running off the bottom edge, inside a panel with rounded top corners.
let panel = CGRect(x: 690, y: 64, width: 440, height: CGFloat(H) - 64)
let cropTop = 0.13 * CGFloat(shot.height)           // skip the screenshot's own headline
let crop = shot.cropping(to: CGRect(x: 0, y: cropTop, width: CGFloat(shot.width),
                                    height: CGFloat(shot.height) - cropTop))!
let scale = panel.width / CGFloat(crop.width)
cg.saveGState()
let r: CGFloat = 26
let clip = CGMutablePath()
clip.move(to: CGPoint(x: panel.minX, y: panel.maxY))
clip.addLine(to: CGPoint(x: panel.minX, y: panel.minY + r))
clip.addArc(tangent1End: CGPoint(x: panel.minX, y: panel.minY),
            tangent2End: CGPoint(x: panel.minX + r, y: panel.minY), radius: r)
clip.addLine(to: CGPoint(x: panel.maxX - r, y: panel.minY))
clip.addArc(tangent1End: CGPoint(x: panel.maxX, y: panel.minY),
            tangent2End: CGPoint(x: panel.maxX, y: panel.minY + r), radius: r)
clip.addLine(to: CGPoint(x: panel.maxX, y: panel.maxY))
clip.closeSubpath()
cg.addPath(clip)
cg.clip()
drawImage(crop, in: CGRect(x: panel.minX, y: panel.minY,
                           width: panel.width, height: CGFloat(crop.height) * scale))
cg.restoreGState()

// Left: icon, name, tagline, availability.
let left: CGFloat = 84, colW: CGFloat = 540
let iconRect = CGRect(x: left, y: 112, width: 112, height: 112)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: 10), blur: 30,
             color: NSColor(srgbRed: 0.086, green: 0.078, blue: 0.059, alpha: 0.28).cgColor)
cg.addPath(CGPath(roundedRect: iconRect, cornerWidth: 25, cornerHeight: 25, transform: nil))
NSColor.white.setFill()
cg.fillPath()
cg.restoreGState()
cg.saveGState()
cg.addPath(CGPath(roundedRect: iconRect, cornerWidth: 25, cornerHeight: 25, transform: nil))
cg.clip()
drawImage(icon, in: iconRect)
cg.restoreGState()

var y: CGFloat = 262
y += drawText("Archipic", font: .systemFont(ofSize: 88, weight: .bold), color: ink,
              at: CGPoint(x: left - 4, y: y), width: colW, kern: -2.6)
y += 10
_ = drawText("A private photo journal for architects.", font: .systemFont(ofSize: 36, weight: .regular),
             color: ink2, at: CGPoint(x: left, y: y), width: 470, lineHeight: 1.08)
_ = drawText("Free for iPhone and iPad", font: .systemFont(ofSize: 24, weight: .medium),
             color: ink3, at: CGPoint(x: left, y: 520), width: colW)

NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath) (\(W)×\(H)) from \(shotPath)")
