import Foundation
import SwiftData

/// Self-contained local backup: writes every photo's pixels (owned photos from
/// their bytes, references resolved from Photos) plus a JSON manifest of all
/// tags / date / GPS / project into a folder, which the user saves to Files (or
/// AirDrops). Because the pixels travel with the backup, it restores onto a
/// fresh install or another device even if the original Photos asset is gone.
enum BackupManager {
    /// One photo's metadata in the manifest. The image bytes live as separate
    /// files (images/<id>.jpg, labels/<id>.jpg) so the JSON stays small.
    struct Record: Codable {
        let id: String
        let createdAt: Date
        let latitude: Double?
        let longitude: Double?
        let project: String?
        let importedAt: Date?
        let humanTags: HumanTags
        let hasLabel: Bool
        // Kept so a reference can relink in place when its asset still exists.
        // Optional so old backups still decode.
        var assetLocalID: String?
        var isCameraShot: Bool?
        // Video: `isVideo` marks the record; `hasVideo` means a movie file is
        // bundled at videos/<id>.mov (only for in-app fallback clips — library
        // references relink from Photos instead of bloating the backup).
        var isVideo: Bool? = nil
        var hasVideo: Bool? = nil
    }

    struct RestoreResult { let added: Int; let missingReferences: Int }

    static let folderName = "Archi.vé Backup"

    /// Builds a self-contained backup folder and returns its URL. Reference pixels
    /// are resolved from Photos (capped at 3072 px so backing up a large library
    /// can't OOM), so the backup stands alone. Async for that reason.
    static func makeBackup(_ photos: [Photo]) async throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? fm.removeItem(at: root)
        let imagesDir = root.appendingPathComponent("images", isDirectory: true)
        let labelsDir = root.appendingPathComponent("labels", isDirectory: true)
        let videosDir = root.appendingPathComponent("videos", isDirectory: true)
        try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: labelsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: videosDir, withIntermediateDirectories: true)

        var records: [Record] = []
        for p in photos {
            // Pixels: owned photos already hold them; references are resolved from
            // Photos (one at a time, so memory stays bounded).
            var pixels: Data? = p.imageData.isEmpty ? nil : p.imageData
            if pixels == nil, let id = p.assetLocalID, !id.isEmpty,
               let img = await PhotosLibrary.image(localID: id, maxPixel: 3072) {
                pixels = img.jpegData(compressionQuality: 0.9)
            }
            if let pixels { try pixels.write(to: imagesDir.appendingPathComponent("\(p.id).jpg")) }

            var hasLabel = false
            if let label = p.labelImageData {
                try label.write(to: labelsDir.appendingPathComponent("\(p.id).jpg"))
                hasLabel = true
            }
            // Bundle the movie only for in-app fallback clips (no Photos home).
            // Library-reference videos relink from Photos on restore — bundling
            // every full movie would balloon the backup.
            var hasVideo = false
            if p.isVideo, let vdata = p.videoData, !vdata.isEmpty {
                try vdata.write(to: videosDir.appendingPathComponent("\(p.id).mov"))
                hasVideo = true
            }
            records.append(Record(id: p.id, createdAt: p.createdAt,
                                  latitude: p.latitude, longitude: p.longitude,
                                  project: p.project, importedAt: p.importedAt,
                                  humanTags: p.humanTags, hasLabel: hasLabel,
                                  assetLocalID: p.assetLocalID, isCameraShot: p.isCameraShot,
                                  isVideo: p.isVideo ? true : nil, hasVideo: hasVideo ? true : nil))
        }

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        try enc.encode(records).write(to: root.appendingPathComponent("manifest.json"))
        return root
    }

    /// Restores from a backup folder, skipping ids already present. Prefers the
    /// bundled pixels (restoring a former reference as an owned photo so it always
    /// displays); for a reference from an OLD backup with no bundled image, it is
    /// restored only if its Photos asset still resolves — otherwise it is counted
    /// as missing rather than inserted as a permanent blank tile.
    @discardableResult
    static func restore(from folder: URL, into context: ModelContext, existingIDs: Set<String>) throws -> RestoreResult {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let records = try dec.decode([Record].self, from: data)

        var added = 0, missing = 0
        for r in records where !existingIDs.contains(r.id) {
            let label: Data? = r.hasLabel
                ? (try? Data(contentsOf: folder.appendingPathComponent("labels/\(r.id).jpg")))
                : nil
            let bundled = try? Data(contentsOf: folder.appendingPathComponent("images/\(r.id).jpg"))
            let aid = r.assetLocalID ?? ""

            // Video records: own the clip when a movie is bundled (in-app
            // fallback), else relink the Photos reference; skip if neither is
            // available (the movie is gone and we can't play a poster).
            if r.isVideo == true {
                let poster = bundled ?? Data()
                let movie = r.hasVideo == true
                    ? (try? Data(contentsOf: folder.appendingPathComponent("videos/\(r.id).mov")))
                    : nil
                if let movie, !movie.isEmpty {
                    let photo = Photo(id: r.id, imageData: poster, createdAt: r.createdAt,
                                      latitude: r.latitude, longitude: r.longitude,
                                      humanTags: r.humanTags, project: r.project,
                                      importedAt: r.importedAt, labelImageData: label,
                                      isVideo: true, videoData: movie)
                    context.insert(photo); added += 1
                } else if !aid.isEmpty, PhotosLibrary.asset(localID: aid) != nil {
                    // Keep the bundled (framing-cropped) poster so the video shows
                    // its aspect in the gallery; the movie relinks from Photos.
                    let photo = Photo(id: r.id, imageData: poster, createdAt: r.createdAt,
                                      latitude: r.latitude, longitude: r.longitude,
                                      humanTags: r.humanTags, project: r.project,
                                      importedAt: r.importedAt, labelImageData: label,
                                      assetLocalID: aid, isCameraShot: r.isCameraShot ?? false, isVideo: true)
                    context.insert(photo); added += 1
                } else {
                    missing += 1
                }
                continue
            }

            let imageData: Data
            let assetID: String?
            if let bundled, !bundled.isEmpty {
                imageData = bundled; assetID = nil            // self-contained → own the pixels
            } else if !aid.isEmpty {
                // Old backup, no bundled pixels: only restore if the original
                // Photos asset still resolves, else skip (no permanent blank tile).
                guard PhotosLibrary.asset(localID: aid) != nil else { missing += 1; continue }
                imageData = Data(); assetID = aid
            } else {
                continue                                       // owned photo, no pixels on disk — skip
            }
            let isCam = (assetID != nil) ? (r.isCameraShot ?? false) : false
            let photo = Photo(id: r.id, imageData: imageData, createdAt: r.createdAt,
                              latitude: r.latitude, longitude: r.longitude,
                              humanTags: r.humanTags, project: r.project,
                              importedAt: r.importedAt, labelImageData: label,
                              assetLocalID: assetID, isCameraShot: isCam)
            context.insert(photo)
            added += 1
        }
        if added > 0 { try context.save() }
        reconcileDuplicates(in: context)
        return RestoreResult(added: added, missingReferences: missing)
    }

    /// Merge accidental same-id duplicate rows (possible because `Photo` has no
    /// CloudKit `.unique` constraint and a restore can race the iCloud mirror).
    /// Keeps the richest copy per id (real pixels first, then tagged over untagged)
    /// and deletes the rest. Only ever removes EXACT-id duplicates, so it can never
    /// merge two genuinely different photos.
    static func reconcileDuplicates(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<Photo>()) else { return }
        let groups = Dictionary(grouping: all, by: { $0.id })
        var changed = false
        // Skip empty ids: a CloudKit field-drop can blank `id`, and grouping those
        // together would treat genuinely different photos as duplicates.
        for (gid, dupes) in groups where !gid.isEmpty && dupes.count > 1 {
            // "Has pixels" counts a Photos reference (assetLocalID) as well as
            // inline bytes, so a tagged reference is never discarded in favour of an
            // owned-but-untagged copy. Ties then break toward the tagged record.
            func score(_ p: Photo) -> Int {
                let hasPixels = !p.imageData.isEmpty || !(p.assetLocalID ?? "").isEmpty
                return (hasPixels ? 2 : 0) + (p.isUntagged ? 0 : 1)
            }
            let keep = dupes.max { score($0) < score($1) }
            for p in dupes where p !== keep { context.delete(p); changed = true }
        }
        if changed { try? context.save() }
    }
}
