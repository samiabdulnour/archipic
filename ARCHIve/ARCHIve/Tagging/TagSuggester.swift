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
        return labels.isEmpty ? nil : map(labels)
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

    /// Short human-readable summary of a suggestion for the banner, e.g. "Building · Office".
    static func summary(_ t: HumanTags) -> String {
        let kind = t.type?.capitalized ?? ""
        let hint = t.typology ?? t.elementCategory ?? t.graphicKind?.capitalized
        return [kind, hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
