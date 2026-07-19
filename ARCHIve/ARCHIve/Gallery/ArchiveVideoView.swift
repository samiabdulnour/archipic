import SwiftUI
import AVKit

/// Plays a Photo record that is a video — from the Photos library when it's a
/// reference, or from the in-app fallback bytes otherwise. The poster still is
/// shown while the playable asset loads (references download from iCloud on
/// demand).
///
/// The movie is recorded full-sensor; the chosen framing (aspect) is applied at
/// display time by aspect-filling the video into its (framing-cropped) poster
/// shape — so playback matches the gallery thumbnail and what was framed.
struct ArchiveVideoView: View {
    let photo: Photo
    var poster: UIImage?

    @State private var player: AVPlayer?
    @State private var tempURL: URL?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let player {
                AspectFillPlayer(player: player)
            } else {
                if let poster {
                    Image(uiImage: poster).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Palette.tile)
                }
                if failed {
                    // The movie couldn't be resolved — an iCloud reference that
                    // isn't downloaded (offline), or a clip removed from Photos.
                    // Show the poster with a clear badge + retry instead of an
                    // endless spinner.
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.icloud").font(.system(size: 34, weight: .light))
                        Text("Video unavailable").font(.footnote.weight(.medium))
                        Button("Retry") { failed = false; Task { await load() } }
                            .buttonStyle(.bordered).tint(.white)
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .clipped()
        .task(id: photo.id) { await load() }
        .onDisappear {
            player?.pause()
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        }
    }

    private func load() async {
        failed = false
        // In-app fallback copy (Photos wasn't available at capture): play the bytes.
        if let data = photo.videoData, !data.isEmpty, let url = VideoTools.writeTemp(data) {
            tempURL = url
            player = AVPlayer(url: url)
            return
        }
        // Reference: pull the AVAsset from Photos (downloads from iCloud if needed).
        if let id = photo.assetLocalID, !id.isEmpty, let asset = await PhotosLibrary.avAsset(localID: id) {
            player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            return
        }
        failed = true
    }
}

/// AVPlayerViewController wrapper that fills (crops to) its bounds, so the
/// full-sensor movie displays cropped to the framing aspect of its container —
/// with the native playback controls. `VideoPlayer` can only letterbox.
private struct AspectFillPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.videoGravity = .resizeAspectFill
        vc.showsPlaybackControls = true
        vc.view.backgroundColor = .black
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
