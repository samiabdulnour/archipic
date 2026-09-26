// Looks preview — renders every camera look on a folder of photos into one
// contact sheet, using the REAL engine (Archipic/.../CameraProcessing.swift).
// No app, no device. Build + run via preview.sh, or:
//   swiftc -O render.swift ../../Archipic/Archipic/Camera/CameraProcessing.swift -o render
//   ./render /path/to/folder-of-photos
// Output: <folder>/_looks-preview.png  (rows = photos, columns = looks).
import AppKit
import CoreImage

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"]
let files = (((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
    .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix("_looks") }
    .sorted())
    .map { (dir as NSString).appendingPathComponent($0) }
guard !files.isEmpty else { print("No images found in \(dir)"); exit(1) }

let looks = CameraLook.allCases
let ctx = CIContext(options: nil)
let tw: CGFloat = 300, gap: CGFloat = 8, labelH: CGFloat = 30

// Load + downscale (so rendering 11 looks × N photos stays fast).
func load(_ path: String) -> CIImage? {
    guard let d = NSImage(contentsOfFile: path)?.tiffRepresentation,
          let rep = NSBitmapImageRep(data: d),
          let cg = rep.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    var ci = CIImage(cgImage: cg)
    let longest = max(ci.extent.width, ci.extent.height)
    if longest > 1200 { let f = 1200 / longest; ci = ci.transformed(by: CGAffineTransform(scaleX: f, y: f)) }
    return ci
}
let sources = files.compactMap(load)
guard !sources.isEmpty else { print("Could not decode any images in \(dir)"); exit(1) }

let rowH = sources.map { tw * ($0.extent.height / max(1, $0.extent.width)) }
let cols = looks.count
let W = CGFloat(cols) * tw + CGFloat(cols + 1) * gap
let H = labelH + rowH.reduce(0, +) + CGFloat(sources.count + 1) * gap

let canvas = NSImage(size: NSSize(width: W, height: H))
canvas.lockFocusFlipped(true)
NSColor(white: 0.12, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
for (c, look) in looks.enumerated() {
    (look.rawValue as NSString).draw(at: NSPoint(x: gap + CGFloat(c) * (tw + gap) + 3, y: 8), withAttributes: attrs)
}
var y = labelH + gap
for (r, src) in sources.enumerated() {
    let th = rowH[r]
    for (c, look) in looks.enumerated() {
        let out = CameraProcessing.colored(src, look: look)
        let scale = tw / out.extent.width
        let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { continue }
        NSImage(cgImage: cg, size: .zero).draw(in: NSRect(x: gap + CGFloat(c) * (tw + gap), y: y, width: tw, height: th))
    }
    y += th + gap
}
canvas.unlockFocus()
let outPath = (dir as NSString).appendingPathComponent("_looks-preview.png")
try! NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    .representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: outPath))
print("Wrote \(sources.count) photos × \(looks.count) looks → \(outPath)")
