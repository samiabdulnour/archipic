import AVFoundation
import UIKit

/// Small helpers for the video feature: a poster still for thumbnails/boards,
/// and spilling in-app movie bytes to a temp file so an AVPlayer can play them.
enum VideoTools {
    /// First-frame poster for a movie file, oriented per the track transform.
    /// Used to give a video record a still `imageData` so the whole image-only
    /// display pipeline (grid, boards, share) keeps working unchanged.
    static func posterFrame(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1600, height: 1600)
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        do {
            let (cg, _) = try await gen.image(at: time)
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }

    /// Write movie bytes to a temp `.mov` so an AVPlayer can play them. Used for
    /// the in-app fallback copy kept when saving to Photos wasn't permitted.
    static func writeTemp(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
