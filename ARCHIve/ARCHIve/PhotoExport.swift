import ImageIO
import UniformTypeIdentifiers
import UIKit

/// Exports a Photo to a JPEG file with its tags written into the image metadata
/// — IPTC keywords + caption, title, creator, star rating — plus the original
/// capture date and GPS (unless stripped). So the archive's tags survive an
/// export into Lightroom / Bridge / InDesign instead of being left behind.
/// On-device, ImageIO only, no new dependency.
enum PhotoExport {
    /// A temp-file JPEG with metadata, for the share sheet. Nil if pixels can't load.
    @MainActor static func jpegURL(for photo: Photo, includeGPS: Bool) async -> URL? {
        guard let image = await PhotoImage.full(for: photo), let cg = image.cgImage else { return nil }
        let props = metadata(for: photo, includeGPS: includeGPS)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(exportName(for: photo)).jpg")
        try? FileManager.default.removeItem(at: url)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? url : nil
    }

    private static func metadata(for photo: Photo, includeGPS: Bool) -> [CFString: Any] {
        let t = photo.humanTags
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]

        // Original capture date (EXIF + TIFF), "yyyy:MM:dd HH:mm:ss".
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let dateStr = df.string(from: photo.createdAt)
        props[kCGImagePropertyExifDictionary] = [
            kCGImagePropertyExifDateTimeOriginal: dateStr,
            kCGImagePropertyExifDateTimeDigitized: dateStr,
        ]
        var tiff: [CFString: Any] = [kCGImagePropertyTIFFDateTime: dateStr]
        if let note = t.note?.trimmed, !note.isEmpty { tiff[kCGImagePropertyTIFFImageDescription] = note }
        if let creator = t.creator?.trimmed, !creator.isEmpty { tiff[kCGImagePropertyTIFFArtist] = creator }
        props[kCGImagePropertyTIFFDictionary] = tiff

        // IPTC: keywords, caption, title (Object Name), creator (By-line), rating.
        var iptc: [CFString: Any] = [:]
        let kw = keywords(for: photo)
        if !kw.isEmpty { iptc[kCGImagePropertyIPTCKeywords] = kw }
        if let note = t.note?.trimmed, !note.isEmpty { iptc[kCGImagePropertyIPTCCaptionAbstract] = note }
        if let title = t.title?.trimmed, !title.isEmpty { iptc[kCGImagePropertyIPTCObjectName] = title }
        if let creator = t.creator?.trimmed, !creator.isEmpty { iptc[kCGImagePropertyIPTCByline] = [creator] }
        if let r = t.rating, r > 0 { iptc[kCGImagePropertyIPTCStarRating] = r }
        if !iptc.isEmpty { props[kCGImagePropertyIPTCDictionary] = iptc }

        // GPS (kept by default; the owner can strip it for public sharing).
        if includeGPS, let lat = photo.latitude, let lon = photo.longitude {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(lat),
                kCGImagePropertyGPSLatitudeRef: lat >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude: abs(lon),
                kCGImagePropertyGPSLongitudeRef: lon >= 0 ? "E" : "W",
            ]
        }
        return props
    }

    /// Flatten the taxonomy + free keywords into a de-duplicated keyword list.
    private static func keywords(for photo: Photo) -> [String] {
        let t = photo.humanTags
        var kw: [String?] = [t.type, t.typology, t.room, t.elementCategory, t.element,
                             t.graphicKind, t.place, photo.project]
        kw += (t.concepts + t.materials + t.colors + t.visual + t.keywords).map { Optional($0) }
        let cleaned = kw.compactMap { $0?.trimmed }.filter { !$0.isEmpty }
        var seen = Set<String>()
        return cleaned.filter { seen.insert($0.lowercased()).inserted }
    }

    /// A readable filename: the plate's title/typology + the capture date.
    private static func exportName(for photo: Photo) -> String {
        let t = photo.humanTags
        let base = [t.title, t.typology, t.element, t.type?.capitalized]
            .compactMap { $0?.trimmed }.first(where: { !$0.isEmpty }) ?? "Archipic"
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        return "\(base) \(df.string(from: photo.createdAt))".replacingOccurrences(of: "/", with: "-")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
