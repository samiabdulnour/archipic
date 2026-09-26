import Foundation
import SwiftData
import UIKit

/// Drains items dropped into the App Group "Inbox" by the Share extension.
///
/// The extension can't touch the SwiftData store, so it writes each shared image
/// as `<id>.jpg` plus a tiny `<id>.json` sidecar (the chosen Kind + a timestamp).
/// The app calls `drain` on launch and on returning to the foreground, turns each
/// item into a tagged `Photo`, then deletes the files. This is the conservative
/// "inbox file" path — the store never moves.
enum ShareInbox {
    static let appGroup = "group.com.samiabdulnour.archive"

    private static var inboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Import every complete item in the inbox into `context`. Safe to call often;
    /// a no-op when the inbox is empty.
    @MainActor
    static func drain(into context: ModelContext) {
        let fm = FileManager.default
        guard let inbox = inboxURL,
              let files = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
        else { return }

        // Drive off the .json sidecars: it's written last, and atomically, so its
        // presence means the matching .jpg is fully on disk.
        for json in files where json.pathExtension == "json" {
            let id = json.deletingPathExtension().lastPathComponent
            let jpg = inbox.appendingPathComponent("\(id).jpg")

            guard let imageData = try? Data(contentsOf: jpg), !imageData.isEmpty,
                  let metaData = try? Data(contentsOf: json),
                  let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any]
            else {
                // Corrupt or orphaned: there's nothing to save, so binning it is safe.
                try? fm.removeItem(at: json); try? fm.removeItem(at: jpg)
                continue
            }

            let importedAt = (meta["importedAt"] as? TimeInterval)
                .map { Date(timeIntervalSince1970: $0) } ?? Date()
            var tags = HumanTags()
            tags.type = meta["type"] as? String   // "building" | "element" | "graphic"

            // A copy in the archive (no assetLocalID → not a Photos-library
            // reference), tagged with the chosen Kind and marked imported.
            let photo = Photo(imageData: imageData,
                              createdAt: importedAt,
                              humanTags: tags,
                              importedAt: importedAt,
                              isCameraShot: false)
            context.insert(photo)

            // Commit BEFORE deleting the source. Deleting first meant a failed save
            // — or being killed mid-drain — destroyed the only copy of the photo.
            // Now a failure just leaves the item for the next launch to retry.
            do {
                try context.save()
                try? fm.removeItem(at: json)
                try? fm.removeItem(at: jpg)
            } catch {
                context.delete(photo)   // drop the pending insert so a retry can't duplicate
                return                  // saving is failing; leave the rest for next time
            }
        }

        // Sweep images whose sidecar never arrived (extension killed mid-write).
        // Age-guarded so this can't race an extension that is writing right now.
        let cutoff = Date().addingTimeInterval(-3600)
        for jpg in files where jpg.pathExtension == "jpg" {
            let sidecar = jpg.deletingPathExtension().appendingPathExtension("json")
            guard !fm.fileExists(atPath: sidecar.path),
                  let modified = try? jpg.resourceValues(forKeys: [.contentModificationDateKey])
                      .contentModificationDate,
                  modified < cutoff
            else { continue }
            try? fm.removeItem(at: jpg)
        }
    }
}
