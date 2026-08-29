import SwiftUI

/// First-run welcome / about screen — app identity, a short lede, and the
/// camera-layout legend, mirroring the web app's welcome page.
struct WelcomeView: View {
    var onGetStarted: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Archipic")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("by Sami Abdulnour").font(.subheadline).foregroundStyle(Palette.ink3)
                }
                Text("A fast, private journal for the architecture you notice — capture in a tap, tag in two, and find it again later by time, reference, project, or place.")
                    .font(.callout).foregroundStyle(Palette.ink2)

                Text("THE CAMERA").font(.caption.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(Palette.coral)

                ForEach(CameraGuide.steps) { step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(step.n)")
                            .font(.headline.weight(.bold)).foregroundStyle(.black)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(step.tint))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title).font(.subheadline.weight(.semibold))
                            Text(step.body).font(.caption).foregroundStyle(Palette.ink3)
                        }
                    }
                }

                Text("TAG, BROWSE & MAKE").font(.caption.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(Palette.coral).padding(.top, 8)

                ForEach(AppGuide.features) { f in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: f.icon)
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(f.tint))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.title).font(.subheadline.weight(.semibold))
                            Text(f.body).font(.caption).foregroundStyle(Palette.ink3)
                        }
                    }
                }

                Button(action: onGetStarted) {
                    Text("Get started").font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent).tint(Palette.coral)
                .padding(.top, 6)
            }
            .padding(24)
        }
        .background(Palette.paper.ignoresSafeArea())
    }
}

/// Shared camera-layout legend, used by Welcome and How-to-use.
enum CameraGuide {
    struct Step: Identifiable {
        let id = UUID(); let n: Int; let title: String; let tint: Color; let body: String
    }
    static let steps: [Step] = [
        .init(n: 1, title: "Project", tint: Palette.coral,
              body: "Top-left: tap to file shots into a project — or leave it Unfiled for things found out in the world. Optional."),
        .init(n: 2, title: "Tag · Reuse · Tilt · More", tint: Palette.mint,
              body: "Top-right. The tag icon toggles Lite ↔ Full; Reuse applies your last photo's tags; Tilt straightens verticals; the dots open camera settings."),
        .init(n: 3, title: "Shutter", tint: Palette.lemon,
              body: "Tap to capture. Full opens tagging right after; Lite saves instantly to tag later. In Video it records."),
        .init(n: 4, title: "Gallery", tint: Palette.coral,
              body: "Bottom-left shows your latest capture — tap to jump into the archive."),
        .init(n: 5, title: "Photo vs Video", tint: Palette.mint,
              body: "Switch the shutter between a still and a movie. Video records straight HD with sound; film looks apply to photos."),
        .init(n: 6, title: "Flip camera", tint: Palette.lemon,
              body: "Bottom-right — switch between the rear and front cameras."),
    ]
}

/// What the app does beyond capture — shown in About and on the first-run welcome.
enum AppGuide {
    struct Feature: Identifiable {
        let id = UUID(); let icon: String; let title: String; let tint: Color; let body: String
    }
    static let features: [Feature] = [
        .init(icon: "tag.fill", title: "Tag in two taps", tint: Palette.coral,
              body: "After a shot, pick the Kind, then the details. Tap any photo in the gallery to retag it anytime, and add a Place (city) or Project."),
        .init(icon: "square.grid.2x2.fill", title: "Browse the archive", tint: Palette.mint,
              body: "Filter by Time, Reference (what's in the photo), Project, or Place on a map. Search across every tag, and pinch the grid to resize it."),
        .init(icon: "camera.filters", title: "Film looks", tint: Palette.lemon,
              body: "In the camera, Effect applies film simulations — Portra, Superia, CineStill and more — each with a best-for time-of-day / weather hint."),
        .init(icon: "crop.rotate", title: "Edit, non-destructively", tint: Palette.coral,
              body: "Open a photo and Edit to crop, straighten (tilt), rotate, and change the look. Your original is never altered — edits are reversible."),
        .init(icon: "photo.on.rectangle.angled", title: "Tag from Photos", tint: Palette.mint,
              body: "Bring in shots already in your library and tag them — one by one, or many at once. Drag across thumbnails to paint a selection."),
        .init(icon: "doc.richtext.fill", title: "Boards & Journals", tint: Palette.lemon,
              body: "Select photos in the gallery, tap Board, and lay them out as a printable catalogue poster (B1) or a chronological journal (A4). Export a PDF to print, save, or share."),
        .init(icon: "lock.icloud.fill", title: "Private & synced", tint: Palette.coral,
              body: "Everything stays on your device and syncs through your own iCloud — no account, no ads, no tracking."),
    ]
}
