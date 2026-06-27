import Foundation
import SwiftData

/// One archived photo plus its human tags and (reserved) machine tags.
///
/// Mirrors the web app's record shape: a JPEG blob, a capture timestamp,
/// optional GPS, and two strictly-separate tag bags — `tagsHuman` (the
/// owner's Kind + Context answers) and `tagsMachine` (reserved for future
/// image-recognition suggestions; empty for now, never merged with human
/// tags so intent and guesses stay distinguishable forever).
@Model
final class Photo: Identifiable {
    /// Stable id (UUID string) — matches the web app's record id style.
    /// NB: no `.unique` constraint — CloudKit sync doesn't allow it; uniqueness
    /// is guaranteed by generating UUIDs and de-duping by id on restore/import.
    var id: String = ""

    /// The captured JPEG. Stored outside the main store file for size.
    @Attribute(.externalStorage) var imageData: Data = Data()

    /// When the photo was taken (capture time, not import time).
    var createdAt: Date = Date()

    // GPS comes free from the phone; nil when unavailable / denied.
    var latitude: Double?
    var longitude: Double?

    /// The owner's structured tags. Encoded JSON so the shape can evolve
    /// without a SwiftData migration for every taxonomy tweak.
    var humanTagsData: Data = Data()

    /// Reserved for machine-suggested tags. Empty for now.
    var machineTagsData: Data = Data()

    /// Project association (editable later); nil = unfiled.
    var project: String?

    /// User-marked favourite — shown with a thin red frame in the gallery.
    var isFavorite: Bool = false

    /// When set, this record is a *reference* to a photo in the system Photos
    /// library (no copy is stored). The pixels are loaded on demand from Photos
    /// via this local identifier; `imageData` stays empty for references.
    var assetLocalID: String?

    /// Set when the photo was brought in via Import rather than the camera.
    var importedAt: Date?

    /// True when this reference was created by the in-app camera (the shot was
    /// saved into the Photos library and we keep only a reference). Distinguishes
    /// it from an existing library photo tagged in place — camera shots are never
    /// auto-removed by the library's untagged cleanup, and still use "Capture
    /// label" (camera) rather than "Select label" (library picker).
    var isCameraShot: Bool = false

    /// An optional second photo of an info placard / wall label (e.g. the
    /// painting's caption at an exhibition) — captured instead of typing the
    /// title/artist. Stored outside the main store file like the main image.
    @Attribute(.externalStorage) var labelImageData: Data?

    // MARK: Non-destructive edits
    // Applied on top of the source image when displayed/shared, so the original
    // (in Photos or `imageData`) is never altered and edits stay reversible.

    /// Colour look applied as an edit (CameraLook rawValue); nil = none.
    var editLookRaw: String?
    /// Keystone/tilt correction applied as an edit (−1…1, 0 = none).
    var editKeystone: Double = 0
    /// Rotation in clockwise degrees: 0 / 90 / 180 / 270.
    var editRotation: Int = 0
    /// Crop window in normalised coordinates of the (rotated) image, top-left
    /// origin. Defaults to the full frame (no crop).
    var cropX: Double = 0
    var cropY: Double = 0
    var cropW: Double = 1
    var cropH: Double = 1

    init(
        id: String = UUID().uuidString,
        imageData: Data,
        createdAt: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        humanTags: HumanTags = HumanTags(),
        project: String? = nil,
        importedAt: Date? = nil,
        labelImageData: Data? = nil,
        assetLocalID: String? = nil,
        isCameraShot: Bool = false
    ) {
        self.id = id
        self.imageData = imageData
        self.createdAt = createdAt
        self.latitude = latitude
        self.longitude = longitude
        self.humanTagsData = (try? JSONEncoder().encode(humanTags)) ?? Data()
        self.machineTagsData = Data()
        self.project = project
        self.importedAt = importedAt
        self.labelImageData = labelImageData
        self.assetLocalID = assetLocalID
        self.isCameraShot = isCameraShot
    }

    /// True when the photo's pixels live in the system Photos library.
    var isReference: Bool { (assetLocalID ?? "").isEmpty == false }

    /// True when any non-destructive edit is set (so display can skip the
    /// pipeline entirely for untouched photos).
    var hasEdits: Bool {
        editLookRaw != nil || editKeystone != 0 || editRotation % 360 != 0
            || cropX > 0.0001 || cropY > 0.0001 || cropW < 0.9999 || cropH < 0.9999
    }

    /// Decoded view of the human tags.
    var humanTags: HumanTags {
        get { (try? JSONDecoder().decode(HumanTags.self, from: humanTagsData)) ?? HumanTags() }
        set { humanTagsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// True when the photo has no Kind and no project — shows the red dot.
    var isUntagged: Bool { humanTags.type == nil && (project ?? "").isEmpty }

    /// Denormalised lower-cased text of every tag value, for search (AND
    /// word-match), mirroring the web app's `search_text`.
    var searchText: String {
        let t = humanTags
        var parts: [String?] = [t.type, t.typology, t.room, t.elementCategory, t.element, t.graphicKind,
                                t.authorYear, t.note, t.place, t.title, t.creator, t.year,
                                t.source, t.brand, t.model, t.contactName, t.contactCompany,
                                project]
        parts += t.concepts + t.materials + t.colors + t.visual + t.keywords
        return parts.compactMap { $0 }.joined(separator: " ").lowercased()
    }
}

/// The owner's structured Kind + Context answers. All optional/array so a
/// partially-tagged draft is representable. IDs are lowercase to match the
/// existing web vocabulary (so future data import lines up).
struct HumanTags: Codable, Equatable {
    /// "building" | "element" | "graphic"
    var type: String?

    // Building branch
    var typology: String?          // Residential, Office, ...
    var room: String?              // outdoor, lobby, ...
    var concepts: [String] = []    // form, space, light, ...

    // Element branch
    var elementCategory: String?   // Structure, Vertical, Opening, ...
    var element: String?           // Wall, Column, Stair, ...
    var materials: [String] = []   // Concrete, Brick, ...
    var colors: [String] = []      // white, grey, ... (when sub-element is Paint)

    // Graphic branch
    var graphicKind: String?       // artwork, book, drawing, ...
    var visual: [String] = []      // Colorful, Monochrome, ...
    // Per-graphic-kind detail fields (match the web app)
    var title: String?
    var creator: String?
    var year: String?
    var source: String?
    var brand: String?
    var model: String?
    var contactName: String?
    var contactCompany: String?

    // Free-text extras (optional)
    var authorYear: String?        // "Aalto, 1939" etc.
    var note: String?              // personal note
    var place: String?             // city / place name, typed by hand (shown in board captions)
    var keywords: [String] = []    // free user keywords
    var rating: Int?               // 1...5 stars (optional, off by default)

    /// A draft is "tagged" once a type is chosen.
    var isEmpty: Bool {
        type == nil && typology == nil && room == nil && concepts.isEmpty
            && element == nil && materials.isEmpty && colors.isEmpty
            && graphicKind == nil && visual.isEmpty
            && (authorYear?.isEmpty ?? true) && (note?.isEmpty ?? true)
    }
}

/// A tiny clipboard for human tags — copy one photo's tags, paste onto another.
/// Backed by a single UserDefaults string (JSON) under `TagClipboard.key`, so an
/// `@AppStorage(TagClipboard.key)` in any view shares the same value (and it
/// survives relaunch). Machine tags and the project are never carried.
enum TagClipboard {
    static let key = "copiedTagsJSON"
    static func encode(_ t: HumanTags) -> String {
        guard let d = try? JSONEncoder().encode(t) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
    static func decode(_ s: String) -> HumanTags? {
        guard !s.isEmpty, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HumanTags.self, from: d)
    }
}
