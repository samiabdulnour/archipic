import UIKit
import SwiftUI

/// Which printed artefact to render from a selection (size + layout).
enum BoardLayout: String, CaseIterable, Identifiable {
    case posterB1, posterA2, journalA4
    var id: String { rawValue }
    var label: String {
        switch self {
        case .posterB1: return "Poster · B1"
        case .posterA2: return "Poster · A2"
        case .journalA4: return "Journal · A4"
        }
    }
    var blurb: String {
        switch self {
        case .posterB1: return "Big justified wall catalogue (700×1000 mm)"
        case .posterA2: return "Justified wall catalogue (420×594 mm)"
        case .journalA4: return "Chronological diary, A4 landscape spreads"
        }
    }
    var icon: String {
        switch self {
        case .posterB1, .posterA2: return "rectangle.portrait"
        case .journalA4: return "book"
        }
    }
}

/// Shareable image sizes for social export (px). The layout fills the aspect.
enum BoardImageSize: String, CaseIterable, Identifiable {
    case square, portrait, story
    var id: String { rawValue }
    var label: String {
        switch self {
        case .square:   return "Square · 1:1"
        case .portrait: return "Portrait · 4:5"
        case .story:    return "Story · 9:16"
        }
    }
    var pixels: CGSize {
        switch self {
        case .square:   return CGSize(width: 1080, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1350)
        case .story:    return CGSize(width: 1080, height: 1920)
        }
    }
}

/// One plate on a board: the image plus the caption fields (mapped from a Photo).
struct BoardPlate {
    let image: UIImage?
    let ar: CGFloat          // native width / height — never cropped to a fixed ratio
    let typology: String
    let secondary: String    // e.g. "Building · Opening"
    let materials: String
    let dateLine: String     // display: "place · 2024.05" or "2024.05"
    let date: String         // sortable "2024.05" — used for ordering / month dividers
    let project: String?
    let credit: String?      // "title · creator · year", lowercased
}

/// Renders the PINŽENÝŘI catalog poster (B1, masonry) to a print-ready PDF.
/// Ported 1:1 from the design handoff — all geometry in mm (1 mm = 2.8346 pt),
/// type in pt, system font, native aspect ratios, full caption under each plate.
enum BoardRenderer {
    static let mm: CGFloat = 2.834645669   // pt per mm

    private static let ink   = UIColor(red: 22/255, green: 20/255, blue: 15/255, alpha: 1)
    private static let muted = UIColor(red: 22/255, green: 20/255, blue: 15/255, alpha: 0.62)
    private static let hair  = UIColor(red: 22/255, green: 20/255, blue: 15/255, alpha: 0.10)

    private static func reg(_ p: CGFloat) -> UIFont { .systemFont(ofSize: p, weight: .regular) }
    private static func semi(_ p: CGFloat) -> UIFont { .systemFont(ofSize: p, weight: .semibold) }

    // MARK: One-call render — load full-res images, lay out, write a PDF to /tmp

    /// Loads each photo's pixels, builds plates, renders the chosen layout to a PDF
    /// in the temporary directory, and returns its URL. Order is preserved.
    @MainActor static func makePDF(photos: [Photo], layout: BoardLayout, title: String? = nil) async -> URL? {
        let plates = await buildPlates(photos)
        guard !plates.isEmpty else { return nil }
        let data: Data
        switch layout {
        case .posterB1:  data = posterPDF(plates, widthMM: 700, heightMM: 1000)
        case .posterA2:  data = posterPDF(plates, widthMM: 420, heightMM: 594)
        case .journalA4: data = journalPDF(plates)
        }
        return writeTemp(data, title: title, ext: "pdf")
    }

    /// Render the board as a shareable IMAGE at a social size, with an optional
    /// attribution mark. Same justified-wall layout as the poster, at the target
    /// aspect (never letterboxed).
    @MainActor static func makeImage(photos: [Photo], size: BoardImageSize,
                                     mark: Bool, title: String? = nil) async -> URL? {
        let plates = await buildPlates(photos)
        guard !plates.isEmpty else { return nil }
        let image = posterImage(plates, pixel: size.pixels, mark: mark)
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        return writeTemp(data, title: title, ext: "jpg")
    }

    /// Load each photo's pixels (downsampled + JPEG'd to keep peak memory low),
    /// fill in a geocoded city for captions when missing, and map to plates —
    /// order preserved. Shared by the PDF and image exporters.
    @MainActor private static func buildPlates(_ photos: [Photo]) async -> [BoardPlate] {
        var plates: [BoardPlate] = []
        for p in photos {
            // Auto-fill the city from GPS for captions, when it's missing (sequential
            // so CLGeocoder is happy; cached; never overwrites a hand-typed place).
            if (p.humanTags.place ?? "").isEmpty, let lat = p.latitude, let lon = p.longitude,
               let city = await Geocoder.shared.city(latitude: lat, longitude: lon) {
                var t = p.humanTags; t.place = city; p.humanTags = t
            }
            // Downsample each plate to print size and drain the source bitmap
            // immediately — holding every selected photo at full resolution at once
            // jetsam-kills a large board export. Aspect ratio is preserved, so the
            // layout is identical.
            if let img = await PhotoImage.full(for: p) {
                let small = autoreleasepool { jpegCompressed(downsampled(img, maxPixel: 1600)) }
                plates.append(plate(for: p, image: small))
            }
        }
        return plates
    }

    private static func writeTemp(_ data: Data, title: String?, ext: String) -> URL? {
        let safe = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (safe.isEmpty ? "Archive Board" : safe).replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(ext)")
        try? data.write(to: url)
        return url
    }

    /// Scale an image's long side down to `maxPixel` (no-op if already smaller),
    /// rendered at scale 1 so the pixel count is exactly print size. Keeps the
    /// aspect ratio, so plate layout is unchanged.
    static func downsampled(_ image: UIImage, maxPixel: CGFloat = 1600) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPixel, longest > 0 else { return image }
        let f = maxPixel / longest
        let size = CGSize(width: image.size.width * f, height: image.size.height * f)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// JPEG-encode an image so UIGraphicsPDFRenderer embeds JPEG instead of a raw
    /// uncompressed bitmap. Without this, a B1 poster with 20+ photos hits 150 MB+;
    /// at quality 0.82 it lands around 8–15 MB with no visible difference at print size.
    private static func jpegCompressed(_ image: UIImage, quality: CGFloat = 0.90) -> UIImage {
        guard let data = image.jpegData(compressionQuality: quality),
              let img = UIImage(data: data) else { return image }
        return img
    }

    // MARK: Caption (the shared .ccap language)

    private static func caption(_ p: BoardPlate, scale: CGFloat = 1) -> NSAttributedString {
        let para = NSMutableParagraphStyle(); para.lineHeightMultiple = 1.22
        let cap: CGFloat = 6.6 * scale
        var lines: [(String, UIFont, UIColor)] = [(p.typology, semi(cap), ink)]
        if !p.secondary.isEmpty { lines.append((p.secondary, reg(cap), muted)) }
        if !p.materials.isEmpty { lines.append((p.materials, reg(cap), muted)) }
        lines.append((p.dateLine, reg(cap), muted))
        if let proj = p.project, !proj.isEmpty { lines.append((proj.lowercased(), semi(cap), ink)) }
        if let credit = p.credit, !credit.isEmpty { lines.append((credit, reg(cap), muted)) }
        let s = NSMutableAttributedString()
        for (i, l) in lines.enumerated() {
            s.append(NSAttributedString(string: l.0 + (i == lines.count - 1 ? "" : "\n"),
                attributes: [.font: l.1, .foregroundColor: l.2, .paragraphStyle: para]))
        }
        return s
    }
    private static func capHeight(_ p: BoardPlate, _ w: CGFloat, scale: CGFloat = 1) -> CGFloat {
        ceil(caption(p, scale: scale).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
              options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    // MARK: Poster (JUSTIFIED / wall) — B1 by default, any page size via widthMM/heightMM
    //
    // Photos flow into horizontal ROWS. Each full row is scaled uniformly so its
    // photos + gaps span the content width exactly (flush to both side margins, on
    // every row). Photo heights vary within a row via a stable per-photo factor;
    // photos are centred on the row's mid-line (taller ones bleed above/below,
    // never cropped/stretched). The last short row stays natural size, left-aligned.
    // A caption hangs under each photo (same language as before). Base row height is
    // binary-searched so the whole wall fits the content height — more photos ⇒
    // smaller photos, never an overflow. (Ported from catalog-poster.js `wall*`.)

    /// One photo after row justification (scaled sizes, x-relative frame).
    private struct WallPhoto { let idx: Int; let w: CGFloat; let h: CGFloat }
    /// One justified row: photos, its image-band height (tallest photo), and the
    /// tallest caption in the row (measured at each photo's actual width).
    private struct WallRow { let photos: [WallPhoto]; let imgH: CGFloat; let capH: CGFloat }

    /// Lay out the justified wall and draw it into `cg` (a PDF or bitmap context of
    /// size widthMM×heightMM in points). `footer` fills the reserved bottom band —
    /// the poster's catalogue line, a social attribution mark, or nothing. Shared
    /// by posterPDF and posterImage so there is exactly ONE layout.
    private static func drawPoster(_ plates: [BoardPlate], widthMM: CGFloat, heightMM: CGFloat,
                                   captionScale: CGFloat, cg: CGContext,
                                   footer: (_ x: CGFloat, _ w: CGFloat, _ y: CGFloat) -> Void) {
        let W = widthMM * mm, H = heightMM * mm
        let s = widthMM / 700                       // scale margins/footer with page size
        let MT = 32 * s * mm, MS = 30 * s * mm, MB = 28 * s * mm, FOOT = 16 * s * mm
        let bodyX = MS, bodyY = MT, availW = W - 2 * MS, availH = H - MT - MB - FOOT
        let capGap = 1.5 * mm

        // Build each caption's attributed string once; measuring only re-flows to
        // width (the binary search measures many times).
        let captions = plates.map { caption($0, scale: captionScale) }
        func capH(_ i: Int, _ w: CGFloat) -> CGFloat {
            ceil(captions[i].boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        }

        // Stable per-photo size factor 0.74…1.30 — a deterministic "random" so the
        // wall looks organic but never reflows differently between renders.
        func factor(_ i: Int) -> CGFloat {
            let x = sin(Double(i + 1) * 12.9898) * 43758.5453
            return 0.74 + CGFloat(x - floor(x)) * 0.56
        }

        // Lay out every row at a trial base height; return the rows + total height.
        func wall(_ baseH: CGFloat) -> (rows: [WallRow], hgap: CGFloat, vgap: CGFloat, total: CGFloat) {
            let hgap = baseH * 0.44, vgap = baseH * 0.5
            // 1) Greedy break into rows at pre-scale sizes.
            var raw: [[(idx: Int, h: CGFloat, iw: CGFloat)]] = []
            var cur: [(Int, CGFloat, CGFloat)] = []
            var rowW: CGFloat = 0
            for i in plates.indices {
                let h = baseH * factor(i)
                let iw = max(0.2, plates[i].ar) * h
                if !cur.isEmpty && rowW + hgap + iw > availW { raw.append(cur); cur = []; rowW = 0 }
                rowW += (cur.isEmpty ? 0 : hgap) + iw
                cur.append((i, h, iw))
            }
            if !cur.isEmpty { raw.append(cur) }
            // 2) Justify each row to the full width (short last row stays natural).
            var rows: [WallRow] = []
            for (r, row) in raw.enumerated() {
                let imgSum = row.reduce(0) { $0 + $1.iw }
                let gaps = hgap * CGFloat(max(0, row.count - 1))
                var scale = imgSum > 0 ? (availW - gaps) / imgSum : 1
                if r == raw.count - 1 && imgSum + gaps < availW { scale = 1 }   // last short row: natural
                var photos: [WallPhoto] = []; var imgH: CGFloat = 0; var ch: CGFloat = 0
                for p in row {
                    let w = p.iw * scale, h = p.h * scale
                    photos.append(WallPhoto(idx: p.idx, w: w, h: h))
                    imgH = max(imgH, h)
                    ch = max(ch, capH(p.idx, w))
                }
                rows.append(WallRow(photos: photos, imgH: imgH, capH: ch))
            }
            // 3) Total laid-out height: each row's image band + caption, plus vgaps.
            var total: CGFloat = 0
            for (r, row) in rows.enumerated() {
                total += row.imgH + capGap + row.capH
                if r < rows.count - 1 { total += vgap }
            }
            return (rows, hgap, vgap, total)
        }

        // 4) Binary-search the largest base height whose wall fits the content height.
        var lo = 6 * mm, hi = 95 * mm, best = 6 * mm
        for _ in 0..<22 {
            let mid = (lo + hi) / 2
            if wall(mid).total <= availH { best = mid; lo = mid } else { hi = mid }
        }
        let laid = wall(best)

        UIColor.white.setFill(); cg.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var y = bodyY
        for row in laid.rows {
            var x = bodyX
            for p in row.photos {
                // Centre each photo on the row's mid-line; caption hangs below it.
                let py = y + (row.imgH - p.h) / 2
                let imgRect = CGRect(x: x, y: py, width: p.w, height: p.h)
                drawCover(plates[p.idx].image, in: imgRect, cg)
                hair.setStroke()
                let o = UIBezierPath(rect: imgRect.insetBy(dx: 0.15 * mm, dy: 0.15 * mm)); o.lineWidth = 0.3 * mm; o.stroke()
                captions[p.idx].draw(with: CGRect(x: x, y: py + p.h + capGap, width: p.w, height: row.capH + 4),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                x += p.w + laid.hgap
            }
            y += row.imgH + capGap + row.capH + laid.vgap
        }
        footer(bodyX, availW, H - MB - 15 * s * mm)
    }

    static func posterPDF(_ plates: [BoardPlate], widthMM: CGFloat = 700, heightMM: CGFloat = 1000) -> Data {
        let W = widthMM * mm, H = heightMM * mm
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: W, height: H))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            drawPoster(plates, widthMM: widthMM, heightMM: heightMM, captionScale: 1, cg: cg) { x, w, y in
                drawFooter(plates: plates, x: x, w: w, y: y, sheet: widthMM > 500 ? "b1" : "a2", cg: cg)
            }
        }
    }

    /// Render the justified wall to a bitmap of exactly `pixel` px at that aspect,
    /// with an optional attribution mark in the reserved bottom band. Same layout
    /// as the poster, never letterboxed.
    static func posterImage(_ plates: [BoardPlate], pixel: CGSize, mark: Bool) -> UIImage {
        // A social canvas is far smaller than a B1 sheet, so the print-tiny 6.6pt
        // caption would be unreadable — use a narrower page (photos stay bold) and
        // enlarge the caption. Height follows the target aspect.
        let widthMM: CGFloat = 300
        let heightMM = widthMM * (pixel.height / pixel.width)
        let W = widthMM * mm
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = pixel.width / W        // → exactly pixel.width px wide
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: heightMM * mm), format: fmt).image { ctx in
            let cg = ctx.cgContext
            drawPoster(plates, widthMM: widthMM, heightMM: heightMM, captionScale: 1.7, cg: cg) { x, w, y in
                if mark { drawAttribution(x: x, w: w, y: y, cg: cg) }
            }
        }
    }

    private static func drawCover(_ image: UIImage?, in rect: CGRect, _ cg: CGContext) {
        guard let image else {
            UIColor(red: 0.89, green: 0.87, blue: 0.835, alpha: 1).setFill(); cg.fill(rect); return
        }
        cg.saveGState(); cg.addRect(rect); cg.clip()
        let isz = image.size
        guard isz.width > 0, isz.height > 0 else { cg.restoreGState(); return }
        let scale = max(rect.width / isz.width, rect.height / isz.height)
        let dw = isz.width * scale, dh = isz.height * scale
        image.draw(in: CGRect(x: rect.midX - dw / 2, y: rect.midY - dh / 2, width: dw, height: dh))
        cg.restoreGState()
    }

    private static func drawFooter(plates: [BoardPlate], x: CGFloat, w: CGFloat, y: CGFloat, sheet: String, cg: CGContext) {
        let dates = plates.map { $0.date }.filter { !$0.isEmpty }.sorted()
        let range = dates.isEmpty ? "" : (dates.first == dates.last ? dates.first! : "\(dates.first!)–\(dates.last!)")
        let para = NSMutableParagraphStyle(); para.alignment = .right; para.lineHeightMultiple = 1.4
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "catalogue · \(sheet)\n", attributes: [.font: semi(8.5), .foregroundColor: ink, .paragraphStyle: para]))
        s.append(NSAttributedString(string: "\(plates.count) plates · \(range)\n", attributes: [.font: reg(8.5), .foregroundColor: ink, .paragraphStyle: para]))
        s.append(NSAttributedString(string: String(format: "sequence 01–%02d", plates.count), attributes: [.font: reg(8.5), .foregroundColor: ink, .paragraphStyle: para]))
        s.draw(with: CGRect(x: x, y: y, width: w, height: 15 * mm), options: [.usesLineFragmentOrigin], context: nil)
    }

    /// Social-export attribution: the app mark + wordmark in the reserved bottom
    /// band (never over a photo). Ink on the white ground, like the app icon.
    private static func drawAttribution(x: CGFloat, w: CGFloat, y: CGFloat, cg: CGContext) {
        let d = 6.0 * mm
        let cx = x + d / 2, cy = y + d / 2
        let lw = d * 0.05, ring = d - lw, disc = ring * 0.911
        let c = CGFloat.pi * ring, rl = c / 9, dot = lw * 0.5, long = 0.46 * rl, gap = (rl - long - 2 * dot) / 3
        cg.saveGState()
        cg.setStrokeColor(ink.cgColor); cg.setLineWidth(lw); cg.setLineCap(.round)
        cg.setLineDash(phase: 0, lengths: [long, gap, dot, gap, dot, gap])
        cg.strokeEllipse(in: CGRect(x: cx - ring / 2, y: cy - ring / 2, width: ring, height: ring))
        cg.setLineDash(phase: 0, lengths: [])
        cg.setFillColor(ink.cgColor)
        cg.fillEllipse(in: CGRect(x: cx - disc / 2, y: cy - disc / 2, width: disc, height: disc))
        cg.restoreGState()
        let word = NSAttributedString(string: "Archi.vé", attributes: [.font: semi(11), .foregroundColor: ink])
        let sz = word.size()
        word.draw(at: CGPoint(x: cx + d / 2 + 2 * mm, y: cy - sz.height / 2))
    }

    // MARK: Journal (A4-landscape spread = 2× A5, chronological flow)

    private struct JBlock { let isDivider: Bool; let month: String; let rec: BoardPlate? }

    static func journalPDF(_ plates: [BoardPlate]) -> Data {
        // chronological by date (stable on original order)
        let recs = plates.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map { $0.element }

        // A5 page geometry (mm), spread is two of these side by side
        let PGw = 148.5 * mm, PGh = 210 * mm
        let top = 15 * mm, bottom = 14 * mm, outer = 16 * mm, inner = 10 * mm
        let footH = 7.5 * mm, plateGap = 6 * mm, colGap = 6 * mm, divH = 7.5 * mm, capGap = 1.5 * mm
        let COLS = 4
        let contentW = PGw - outer - inner
        let colW = (contentW - colGap * CGFloat(COLS - 1)) / CGFloat(COLS)
        let colH = PGh - top - bottom - footH

        func plateH(_ r: BoardPlate) -> CGFloat { colW / max(0.2, r.ar) + capGap + capHeight(r, colW) }
        func blockH(_ b: JBlock) -> CGFloat { b.isDivider ? divH : (b.rec.map(plateH) ?? 0) }

        // flatten to blocks, inserting a month divider whenever the month changes
        var blocks: [JBlock] = []
        var lastMonth = ""
        for r in recs {
            let m = String(r.date.prefix(7))
            if m != lastMonth { blocks.append(JBlock(isDivider: true, month: m, rec: nil)); lastMonth = m }
            blocks.append(JBlock(isDivider: false, month: m, rec: r))
        }

        // greedy column packing by height
        var cols: [[JBlock]] = [], cur: [JBlock] = []; var used: CGFloat = 0
        for b in blocks {
            let h = blockH(b), gap = cur.isEmpty ? 0 : plateGap
            if !cur.isEmpty && used + gap + h > colH { cols.append(cur); cur = []; used = 0 }
            cur.append(b); used += (cur.count > 1 ? plateGap : 0) + h
        }
        if !cur.isEmpty { cols.append(cur) }
        // never let a column end on a divider (orphan) — carry it to the next column
        for i in cols.indices.dropLast() where cols[i].last?.isDivider == true {
            let d = cols[i].removeLast(); cols[i + 1].insert(d, at: 0)
        }
        if cols.last?.last?.isDivider == true { cols[cols.count - 1].removeLast() }
        cols.removeAll { $0.isEmpty }

        let spreadW = 297 * mm, spreadH = 210 * mm
        let perSpread = COLS * 2
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: spreadW, height: spreadH))
        return renderer.pdfData { ctx in
            var ci = 0
            while ci < cols.count {
                ctx.beginPage()
                let cg = ctx.cgContext
                UIColor.white.setFill(); cg.fill(CGRect(x: 0, y: 0, width: spreadW, height: spreadH))

                for slot in 0..<perSpread {
                    let idx = ci + slot
                    if idx >= cols.count { break }
                    let page = slot / COLS                  // 0 = left A5, 1 = right A5
                    let colInPage = slot % COLS
                    let pageX = page == 0 ? 0 : PGw
                    let contentX = pageX + (page == 0 ? outer : inner)
                    let x = contentX + CGFloat(colInPage) * (colW + colGap)
                    var y = top
                    for b in cols[idx] {
                        if b.isDivider {
                            drawDivider(b.month, x: x, w: colW, y: y, cg)
                            y += divH + plateGap
                        } else if let r = b.rec {
                            let imgH = colW / max(0.2, r.ar), ch = capHeight(r, colW)
                            let imgRect = CGRect(x: x, y: y, width: colW, height: imgH)
                            drawCover(r.image, in: imgRect, cg)
                            hair.setStroke()
                            let o = UIBezierPath(rect: imgRect.insetBy(dx: 0.15 * mm, dy: 0.15 * mm)); o.lineWidth = 0.3 * mm; o.stroke()
                            caption(r).draw(with: CGRect(x: x, y: y + imgH + capGap, width: colW, height: ch + 4),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                            y += imgH + capGap + ch + plateGap
                        }
                    }
                }
                // per-page date footers, aligned to each page's outer edge
                for page in 0..<2 {
                    let base = ci + page * COLS
                    guard base < cols.count else { break }
                    let pageCols = cols[base..<min(base + COLS, cols.count)]
                    let dates = pageCols.flatMap { $0.compactMap { $0.rec?.date } }
                    let pageX = page == 0 ? CGFloat(0) : PGw
                    let fx = pageX + (page == 0 ? outer : inner)
                    journalFoot(dates, x: fx, w: contentW, y: PGh - bottom - footH + 1 * mm, alignRight: page == 1, cg)
                }
                ci += perSpread
            }
        }
    }

    private static func monthLabel(_ ym: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy.MM"
        guard let d = f.date(from: ym) else { return ym }
        let o = DateFormatter(); o.dateFormat = "MMMM yyyy"; return o.string(from: d).lowercased()
    }
    private static func drawDivider(_ month: String, x: CGFloat, w: CGFloat, y: CGFloat, _ cg: CGContext) {
        NSAttributedString(string: monthLabel(month), attributes: [.font: semi(7), .foregroundColor: ink])
            .draw(at: CGPoint(x: x, y: y))
        let ly = y + 5.5 * mm
        let p = UIBezierPath(); p.move(to: CGPoint(x: x, y: ly)); p.addLine(to: CGPoint(x: x + w, y: ly)); p.lineWidth = 0.3 * mm
        UIColor(red: 22/255, green: 20/255, blue: 15/255, alpha: 0.35).setStroke(); p.stroke()
    }
    private static func journalFoot(_ dates: [String], x: CGFloat, w: CGFloat, y: CGFloat, alignRight: Bool, _ cg: CGContext) {
        let ds = dates.filter { !$0.isEmpty }.sorted()
        guard let lo = ds.first, let hi = ds.last else { return }
        let range = lo == hi ? lo : "\(lo) – \(hi)"
        let para = NSMutableParagraphStyle(); para.alignment = alignRight ? .right : .left
        NSAttributedString(string: range, attributes: [.font: reg(7.5), .foregroundColor: muted, .paragraphStyle: para])
            .draw(with: CGRect(x: x, y: y, width: w, height: 6 * mm), options: [.usesLineFragmentOrigin], context: nil)
    }

    // MARK: Map a Photo → a plate

    static func plate(for photo: Photo, image: UIImage) -> BoardPlate {
        let t = photo.humanTags
        let typ = [t.typology, t.element, t.graphicKind?.capitalized, t.type?.capitalized]
            .compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Untitled"
        var secondary: [String] = []
        if let ty = t.type { secondary.append(ty.capitalized) }
        if let ec = t.elementCategory, !ec.isEmpty { secondary.append(ec) }
        else if let room = t.room, !room.isEmpty { secondary.append(room.capitalized) }
        let materials = t.materials.joined(separator: ", ")
        let df = DateFormatter(); df.dateFormat = "yyyy.MM"
        let dateStr = df.string(from: photo.createdAt)
        let place = t.place?.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateLine = (place?.isEmpty == false) ? "\(place!) · \(dateStr)" : dateStr
        let project = (photo.project?.isEmpty == false) ? photo.project : nil
        var credit: String? = nil
        if let title = t.title, !title.isEmpty {
            credit = [title, t.creator, t.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").lowercased()
        }
        let ar = image.size.height > 0 ? image.size.width / image.size.height : 1
        return BoardPlate(image: image, ar: ar, typology: typ, secondary: secondary.joined(separator: " · "),
                          materials: materials, dateLine: dateLine, date: dateStr,
                          project: project, credit: credit)
    }
}
