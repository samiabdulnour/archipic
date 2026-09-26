import Vision
import UIKit

/// On-device tag suggestion via Apple Vision. Classifies the photo and maps the
/// labels to a partial `HumanTags` guess (Kind + a hint). Fully offline and
/// private — no network, no server. It's a *suggestion* the owner confirms; the
/// raw guess is kept separately in `machineTagsData`, never merged silently.
enum TagSuggester {
    static func suggest(for image: UIImage) async -> HumanTags? {
        guard let cg = image.cgImage else { return nil }
        let labels = await classify(cg)
        guard var t = (labels.isEmpty ? nil : map(labels)) else { return nil }
        // For a graphic (book page, wall label, plan, render) read the text too and
        // pre-fill title / creator / year as further suggestions. OCR runs only for
        // graphics, so it doesn't slow the common building/element case.
        if t.type == "graphic" {
            applyText(await recognizeText(cg), to: &t)
        }
        return t
    }

    private static func classify(_ cg: CGImage) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNClassifyImageRequest()
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
                let obs = req.results ?? []
                let top = obs.filter { $0.confidence > 0.1 }.prefix(15).map { $0.identifier.lowercased() }
                cont.resume(returning: Array(top))
            }
        }
    }

    /// Map Vision's generic labels onto the app's Kind + a coarse sub-tag. Substring
    /// matching keeps it robust to label variants (e.g. "office_building"). This map
    /// is deliberately conservative and will be tuned against real on-device output.
    private static func map(_ ids: [String]) -> HumanTags? {
        func has(_ keys: String...) -> Bool { ids.contains { id in keys.contains { id.contains($0) } } }
        var t = HumanTags()
        if has("book", "text", "document", "paper", "menu", "poster", "drawing", "sketch",
               "painting", "map", "page", "newspaper", "magazine", "whiteboard", "blueprint", "screenshot") {
            t.type = "graphic"
            if has("book", "page", "menu", "newspaper", "magazine") { t.graphicKind = "book" }
            else if has("drawing", "sketch", "map", "blueprint") { t.graphicKind = "drawing" }
            else if has("painting", "art") { t.graphicKind = "artwork" }
        } else if has("window", "door", "stair", "column", "wall", "roof", "ceiling", "floor",
                      "railing", "fence", "balcony", "brick", "tile", "beam", "arch", "gate", "cladding") {
            t.type = "element"
            if has("window", "door", "gate", "arch") { t.elementCategory = "Opening" }
            else if has("stair", "column", "beam", "truss") { t.elementCategory = "Structure" }
            else if has("brick", "tile", "wall", "cladding") { t.elementCategory = "Envelope" }
        } else if has("building", "architecture", "house", "skyscraper", "tower", "church", "temple",
                      "castle", "palace", "monument", "cathedral", "cityscape", "plaza", "courtyard",
                      "interior", "room", "hall", "museum", "library", "park", "garden", "tree",
                      "landscape", "facade", "apartment", "office", "shop", "store", "market") {
            t.type = "building"
            if has("church", "temple", "castle", "palace", "monument", "cathedral") { t.typology = "Heritage" }
            else if has("office", "skyscraper", "tower") { t.typology = "Office" }
            else if has("museum", "library", "hall") { t.typology = "Public" }
            else if has("house", "home", "apartment", "residential") { t.typology = "Residential" }
            else if has("shop", "store", "market", "mall") { t.typology = "Commercial" }
            else if has("park", "garden", "tree", "landscape", "plaza") { t.typology = "Landscape" }
        }
        return t.type == nil ? nil : t
    }

    /// On-device OCR (Vision). Returns each recognised line with its relative text
    /// height, so the most prominent lines (a title on a cover/placard) rank first.
    private static func recognizeText(_ cg: CGImage) async -> [(text: String, height: CGFloat)] {
        await withCheckedContinuation { (cont: CheckedContinuation<[(String, CGFloat)], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
                let lines: [(String, CGFloat)] = (req.results ?? []).compactMap { o in
                    guard let c = o.topCandidates(1).first, c.confidence > 0.3 else { return nil }
                    let s = c.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    return s.isEmpty ? nil : (s, o.boundingBox.height)
                }
                cont.resume(returning: lines)
            }
        }
    }

    /// Pull a title / creator / year out of the OCR'd lines — deliberately
    /// conservative, since these become editable suggestions the owner confirms.
    private static func applyText(_ lines: [(text: String, height: CGFloat)], to t: inout HumanTags) {
        guard !lines.isEmpty else { return }
        // Year: first plausible 4-digit year anywhere in the text.
        if let year = firstYear(lines.map(\.text).joined(separator: " ")) { t.year = year }
        // Rank by prominence = text height × length, so a long title beats a big
        // one-word sign (e.g. "EXIT" over "Villa Savoye").
        func score(_ l: (text: String, height: CGFloat)) -> CGFloat { l.height * CGFloat(min(l.text.count, 40)) }
        let ranked = lines.sorted { score($0) > score($1) }
        // Title: the most prominent line that has letters (not just a number).
        if let title = ranked.first(where: { isTitleish($0.text) })?.text { t.title = title }
        // Creator: the most prominent *name-like* line that isn't the title.
        if let creator = ranked.first(where: { $0.text != t.title && looksLikeName($0.text) })?.text {
            t.creator = creator
        }
    }
    private static func firstYear(_ s: String) -> String? {
        guard let r = s.range(of: #"\b(1[89]\d{2}|20\d{2})\b"#, options: .regularExpression) else { return nil }
        return String(s[r])
    }
    private static func isTitleish(_ s: String) -> Bool {
        s.count >= 3 && s.rangeOfCharacter(from: .letters) != nil
    }
    private static func looksLikeName(_ s: String) -> Bool {
        let particles: Set<String> = ["de", "van", "von", "der", "den", "la", "le", "du", "di", "da", "the"]
        let words = s.split(separator: " ").map(String.init)
        guard (2...4).contains(words.count) else { return false }
        return words.allSatisfy { w in
            if particles.contains(w.lowercased()) { return true }
            guard let f = w.first, f.isUppercase else { return false }
            return w.allSatisfy { $0.isLetter || $0 == "." || $0 == "-" || $0 == "'" }
        }
    }

    /// Short human-readable summary of a suggestion for the banner, e.g. "Building · Office".
    static func summary(_ t: HumanTags) -> String {
        let kind = t.type?.capitalized ?? ""
        let hint = t.typology ?? t.elementCategory ?? t.graphicKind?.capitalized
        return [kind, hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
