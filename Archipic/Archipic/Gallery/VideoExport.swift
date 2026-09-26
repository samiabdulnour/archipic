import AVFoundation

/// Exports a video record cropped to its framing aspect, so a shared/exported
/// file matches what you shot (the stored movie itself is full-sensor; the
/// aspect is a framing crop applied here at export time via a video composition).
enum VideoExport {
    /// Produce a temp .mov cropped to `aspect` (width / height). nil on failure.
    static func croppedFile(for photo: Photo, aspect: CGFloat) async -> URL? {
        // Resolve the source movie (a temp file for the in-app fallback bytes, or
        // the Photos asset for a reference).
        var tempInput: URL?
        let asset: AVAsset
        if let data = photo.videoData, !data.isEmpty, let url = VideoTools.writeTemp(data) {
            tempInput = url
            asset = AVURLAsset(url: url)
        } else if let id = photo.assetLocalID, !id.isEmpty, let a = await PhotosLibrary.avAsset(localID: id) {
            asset = a
        } else {
            return nil
        }
        defer { if let tempInput { try? FileManager.default.removeItem(at: tempInput) } }

        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let duration = try? await asset.load(.duration) else { return nil }

        // Displayed (oriented) size — .applying uses the transform's rotation/scale,
        // ignoring translation; abs() drops any sign flips from the rotation.
        let displayed = naturalSize.applying(transform)
        let dw = abs(displayed.width), dh = abs(displayed.height)
        guard dw > 0, dh > 0 else { return nil }

        // Centered crop to the target aspect, in displayed coordinates.
        var cw = dw, ch = dh
        if dw / dh > aspect { cw = dh * aspect } else { ch = dw / aspect }
        let ox = ((dw - cw) / 2).rounded(), oy = ((dh - ch) / 2).rounded()

        let comp = AVMutableVideoComposition()
        comp.renderSize = CGSize(width: cw.rounded(), height: ch.rounded())
        comp.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        // Orient the frame, then shift the crop region to the render origin.
        layer.setTransform(transform.concatenating(CGAffineTransform(translationX: -ox, y: -oy)), at: .zero)
        instruction.layerInstructions = [layer]
        comp.instructions = [instruction]

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("Archipic-\(photo.id.prefix(6)).mov")
        try? FileManager.default.removeItem(at: out)
        export.outputURL = out
        export.outputFileType = .mov
        export.videoComposition = comp
        export.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { cont in
            export.exportAsynchronously { cont.resume() }
        }
        return export.status == .completed ? out : nil
    }
}
