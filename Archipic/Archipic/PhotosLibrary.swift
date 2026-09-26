import Photos
import UIKit
import CoreLocation
import AVFoundation

/// Thin wrapper over the Photos framework for the "tag your existing library"
/// flow: authorisation, fetching assets, and loading images by local identifier
/// (so a tagged reference shows its picture without storing a copy).
/// Loads a displayable image for a Photo, whether it owns its pixels or
/// references one in the Photos library.
enum PhotoImage {
    /// Screen-grade image for display/zoom/share. Requesting a bounded size
    /// (not the full original) returns the on-device rendition instantly even
    /// under "Optimize iPhone Storage" — no slow iCloud download of the original.
    static func full(for photo: Photo) async -> UIImage? {
        let base: UIImage?
        // A video's poster is stored (already cropped to its framing) in
        // imageData, so use that rather than the full-frame Photos still.
        if photo.isVideo, !photo.imageData.isEmpty {
            base = await PhotoThumbnail.thumbnail(from: photo.imageData, maxPixel: 2400)
        } else if let id = photo.assetLocalID, !id.isEmpty {
            base = await PhotosLibrary.image(localID: id, maxPixel: 2400)
        } else {
            // Downsample owned pixels too (off-main, via CGImageSource) — a
            // full-res 48MP JPEG decoded uncapped here OOMs the detail/zoom/PDF
            // paths just like the camera/editor did.
            base = await PhotoThumbnail.thumbnail(from: photo.imageData, maxPixel: 2400)
        }
        guard let base else { return nil }
        // The photo may have been deleted during the (possibly slow, iCloud)
        // load; reading a deleted SwiftData model's properties throws an
        // uncatchable ObjC exception, so return the raw pixels if it's gone.
        guard photo.modelContext != nil else { return base }
        return (photo.hasEdits && !photo.isVideo) ? PhotoEdits.render(base, photo) : base
    }
}

enum PhotosLibrary {
    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    @discardableResult
    static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { cont.resume(returning: $0) }
        }
    }

    /// Permission to *add* to the library (a subset of read/write — granted
    /// implicitly if the user already allowed full access).
    static func requestAddAuthorization() async -> PHAuthorizationStatus {
        let cur = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if cur != .notDetermined { return cur }
        return await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { cont.resume(returning: $0) }
        }
    }

    /// Save JPEG data into the Photos library and return its local identifier
    /// (so we can store a reference, not a duplicate). `coordinate`, if given,
    /// stamps the asset's location like a Camera shot. nil if not permitted/failed.
    static func saveImage(_ data: Data, coordinate: CLLocationCoordinate2D? = nil) async -> String? {
        let status = await requestAddAuthorization()
        guard status == .authorized || status == .limited else { return nil }
        return await withCheckedContinuation { cont in
            var localID: String?
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
                if let c = coordinate {
                    req.location = CLLocation(coordinate: c, altitude: 0,
                                              horizontalAccuracy: kCLLocationAccuracyHundredMeters,
                                              verticalAccuracy: -1, timestamp: Date())
                }
                localID = req.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, _ in
                cont.resume(returning: success ? localID : nil)
            }
        }
    }

    /// Save a movie file into the Photos library and return its local identifier
    /// (so we store a reference, not a duplicate). Videos must be added from a
    /// file URL, not in-memory Data. nil if not permitted/failed.
    static func saveVideo(fileURL: URL, coordinate: CLLocationCoordinate2D? = nil) async -> String? {
        let status = await requestAddAuthorization()
        guard status == .authorized || status == .limited else { return nil }
        return await withCheckedContinuation { cont in
            var localID: String?
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .video, fileURL: fileURL, options: nil)
                if let c = coordinate {
                    req.location = CLLocation(coordinate: c, altitude: 0,
                                              horizontalAccuracy: kCLLocationAccuracyHundredMeters,
                                              verticalAccuracy: -1, timestamp: Date())
                }
                localID = req.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, _ in
                cont.resume(returning: success ? localID : nil)
            }
        }
    }

    /// Load the playable AVAsset for a video stored in Photos (downloads from
    /// iCloud on demand). nil if the asset is gone or isn't a video.
    static func avAsset(localID: String) async -> AVAsset? {
        guard let asset = asset(localID: localID), asset.mediaType == .video else { return nil }
        return await withCheckedContinuation { cont in
            var resumed = false
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .automatic
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                if !resumed { resumed = true; cont.resume(returning: avAsset) }
            }
        }
    }

    /// All photos (images only), newest first.
    static func fetchImages() -> PHFetchResult<PHAsset> {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return PHAsset.fetchAssets(with: opts)
    }

    static func asset(localID: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject
    }

    static func image(localID: String, maxPixel: CGFloat) async -> UIImage? {
        guard let asset = asset(localID: localID) else { return nil }
        return await image(asset: asset, maxPixel: maxPixel)
    }

    /// Load a (downsampled) image for an asset. `maxPixel == 0` → full size.
    static func image(asset: PHAsset, maxPixel: CGFloat) async -> UIImage? {
        await withCheckedContinuation { cont in
            var resumed = false
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true        // fetch from iCloud if needed
            opts.deliveryMode = .highQualityFormat    // single callback
            opts.resizeMode = .fast
            let target = maxPixel > 0
                ? CGSize(width: maxPixel, height: maxPixel)
                : PHImageManagerMaximumSize
            // Always aspect-fit so the whole image comes back (uncropped); the
            // grid cells fill their square via the view's scaledToFill.
            let mode: PHImageContentMode = .aspectFit
            PHImageManager.default().requestImage(for: asset, targetSize: target,
                                                  contentMode: mode, options: opts) { img, _ in
                if !resumed { resumed = true; cont.resume(returning: img) }
            }
        }
    }
}
