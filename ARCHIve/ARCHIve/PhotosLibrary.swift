import Photos
import UIKit
import CoreLocation

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
        if let id = photo.assetLocalID, !id.isEmpty {
            base = await PhotosLibrary.image(localID: id, maxPixel: 2400)
        } else {
            // Downsample owned pixels too (off-main, via CGImageSource) — a
            // full-res 48MP JPEG decoded uncapped here OOMs the detail/zoom/PDF
            // paths just like the camera/editor did.
            base = await PhotoThumbnail.thumbnail(from: photo.imageData, maxPixel: 2400)
        }
        guard let base else { return nil }
        return photo.hasEdits ? PhotoEdits.render(base, photo) : base
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
