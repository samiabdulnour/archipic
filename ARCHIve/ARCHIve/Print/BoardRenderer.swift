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
        case .posterB1: return "Big masonry catalogue (700×1000 mm)"
        case .posterA2: return "Masonry catalogue (420×594 mm)"
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
        var plates: [BoardPlate] = []
        for p in photos {
            // Auto-fill the city from GPS for captions, when it's missing (sequential
            // so CLGeocoder is happy; cached; never overwrites a hand-typed place).
            if (p.humanTags.place ?? "").isEmpty, let lat = p.latitude, let lon = p.longitude,
               let city = await Geocoder.city(latitude: lat, longitude: lon) {
                var t = p.humanTags; t.place = city; p.humanTags = t
            }
            if let img = await PhotoImage.full(for: p) { plates.append(plate(for: p, image: img)) }
        }
        guard !plates.isEmpty else { return nil }
        let data: Data
        switch layout {
        case .posterB1:  data = posterPDF(plates, widthMM: 700, heightMM: 1000)
        case .posterA2:  data = posterPDF(plates, widthMM: 420, heightMM: 594)
        case .journalA4: data = journalPDF(plates)
        }
        let safe = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (safe.isEmpty ? "Archive Board" : safe).replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        try? data.write(to: url)
        return url
    }

    // MARK: Caption (the shared .ccap language)

    private static func caption(_ p: BoardPlate) -> NSAttributedString {
        let para = NSMutableParagraphStyle(); para.lineHeightMultiple = 1.22
        let cap: CGFloat = 6.6
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
    private static func capHeight(_ p: BoardPlate, _ w: CGFloat) -> CGFloat {
        ceil(caption(p).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
              options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    // MARK: Poster (masonry) — B1 by default, any page size via widthMM/heightMM

    static func posterPDF(_ plates: [BoardPlate], widthMM: CGFloat = 700, heightMM: CGFloat = 1000) -> Data {
        let W = widthMM * mm, H = heightMM * mm
        let s = widthMM / 700                       // scale margins/footer with page size
        let MT = 32 * s * mm, MS = 30 * s * mm, MB = 28 * s * mm, FOOT = 16 * s * mm
        let bodyX = MS, bodyY = MT, bodyW = W - 2 * MS, bodyH = H - MT - MB - FOOT
        let n = max(1, plates.count)
        let GUT = max(5, min(16, 16 - CGFloat(n - 6) * (11.0 / 34.0))) * mm
        let capGap = 1.5 * mm

        // Balanced column layout (emulates CSS column-count): fill each of c
        // columns to ~equal height, so the grid spans the FULL content width with
        // any surplus falling to the bottom — never a staircase that empties the
        // right side. Pick the fewest columns (largest photos) that still fit.
        func layout(_ c: Int) -> (cols: [[Int]], colW: CGFloat, maxH: CGFloat) {
            let w = (bodyW - GUT * CGFloat(c - 1)) / CGFloat(c)
            let blocks = plates.map { w / max(0.2, $0.ar) + capGap + capHeight($0, w) }
            // columns needed if no column may exceed height `cap` (order-preserving)
            func need(_ cap: CGFloat) -> Int {
                var cols = 1, h: CGFloat = 0
                for b in blocks { let g = h > 0 ? GUT : 0
                    if h > 0 && h + g + b > cap { cols += 1; h = b } else { h += g + b } }
                return cols
            }
            // binary-search the SMALLEST column height that still fits in c columns
            // → the most even split possible (min-max partition).
            let maxBlock = blocks.max() ?? 0
            let total = blocks.reduce(0, +) + GUT * CGFloat(max(0, blocks.count - 1))
            var lo = maxBlock, hi = max(maxBlock, total)
            for _ in 0..<48 { let mid = (lo + hi) / 2; if need(mid) <= c { hi = mid } else { lo = mid } }
            let cap = hi
            var cols: [[Int]] = [], cur: [Int] = []; var h: CGFloat = 0
            for i in plates.indices {
                let b = blocks[i], g = cur.isEmpty ? 0 : GUT
                if !cur.isEmpty && h + g + b > cap { cols.append(cur); cur = []; h = 0 }
                cur.append(i); h += (cur.count > 1 ? GUT : 0) + b
            }
            if !cur.isEmpty { cols.append(cur) }
            let maxH = cols.map { col in col.reduce(0) { $0 + blocks[$1] } + GUT * CGFloat(max(0, col.count - 1)) }.max() ?? 0
            return (cols, w, maxH)
        }
        var chosen = layout(7)
        for c in 2...7 { let l = layout(c); if l.maxH <= bodyH { chosen = l; break } }
        let colW = chosen.colW

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: W, height: H))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            UIColor.white.setFill(); cg.fill(CGRect(x: 0, y: 0, width: W, height: H))

            for (ci, colIdx) in chosen.cols.enumerated() {
                let x = bodyX + CGFloat(ci) * (colW + GUT)
                var y = bodyY
                for i in colIdx {
                    let p = plates[i]
                    let imgH = colW / max(0.2, p.ar), ch = capHeight(p, colW)
                    let imgRect = CGRect(x: x, y: y, width: colW, height: imgH)
                    drawCover(p.image, in: imgRect, cg)
                    hair.setStroke()
                    let o = UIBezierPath(rect: imgRect.insetBy(dx: 0.15 * mm, dy: 0.15 * mm)); o.lineWidth = 0.3 * mm; o.stroke()
                    caption(p).draw(with: CGRect(x: x, y: y + imgH + capGap, width: colW, height: ch + 4),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    y += imgH + capGap + ch + GUT
                }
            }
            drawFooter(plates: plates, x: bodyX, w: bodyW, y: H - MB - 15 * s * mm, cg: cg)
        }
    }

    private static func drawCover(_ image: UIImage?, in rect: CGRect, _ cg: CGContext) {
        guard let image else {
            UIColor(red: 0.89, green: 0.87, blue: 0.835, alpha: 1).setFill(); cg.fill(rect); return
        }
        cg.saveGState(); cg.addRect(rect); cg.clip()
        let isz = image.size
        let scale = max(rect.width / isz.width, rect.height / isz.height)
        let dw = isz.width * scale, dh = isz.height * scale
        image.draw(in: CGRect(x: rect.midX - dw / 2, y: rect.midY - dh / 2, width: dw, height: dh))
        cg.restoreGState()
    }

    private static func drawFooter(plates: [BoardPlate], x: CGFloat, w: CGFloat, y: CGFloat, cg: CGContext) {
        let dates = plates.map { $0.date }.filter { !$0.isEmpty }.sorted()
        let range = dates.isEmpty ? "" : (dates.first == dates.last ? dates.first! : "\(dates.first!)–\(dates.last!)")
        let para = NSMutableParagraphStyle(); para.alignment = .right; para.lineHeightMultiple = 1.4
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "catalogue · b1\n", attributes: [.font: semi(8.5), .foregroundColor: ink, .paragraphStyle: para]))
        s.append(NSAttributedString(string: "\(plates.count) plates · \(range)\n", attributes: [.font: reg(8.5), .foregroundColor: ink, .paragraphStyle: para]))
        s.append(NSAttributedString(string: String(format: "sequence 01–%02d", plates.count), attributes: [.font: reg(8.5), .foregroundColor: ink, .paragraphStyle: para]))
        s.draw(with: CGRect(x: x, y: y, width: w, height: 15 * mm), options: [.usesLineFragmentOrigin], context: nil)
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
