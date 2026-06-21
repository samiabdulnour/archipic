import SwiftUI

/// Annotated guide to the camera layout — the native counterpart of the old
/// web app's numbered explainer. A schematic diagram up top maps each numbered
/// badge to the control it points at, then the list explains each in turn.
struct HowToUseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CameraDiagram()
                    .frame(height: 380)
                    .frame(maxWidth: .infinity)

                sectionHeader("THE CAMERA")
                ForEach(CameraGuide.steps) { step in
                    card(badge: AnyView(
                        Text("\(step.n)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(step.tint))
                    ), title: step.title, body: step.body)
                }

                sectionHeader("TAG, BROWSE & MAKE")
                ForEach(AppGuide.features) { f in
                    card(badge: AnyView(
                        Image(systemName: f.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(f.tint))
                    ), title: f.title, body: f.body)
                }
            }
            .padding(16)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("How to use")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).font(.caption.weight(.semibold)).tracking(1.2)
            .foregroundStyle(Palette.coral)
            .padding(.top, 8)
    }

    private func card(badge: AnyView, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            badge
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.tile))
    }
}

/// Feature guide beyond the camera layout — tagging, browsing, and the print
/// (Boards & Journals) and editing features.
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
              body: "Everything stays on your device and syncs through your own iCloud — no account, no ads, no tracking. Export a full backup to Files any time."),
    ]
}

/// A small stylised picture of the camera screen with numbered badges placed on
/// each control, so the list below reads as a legend for the diagram.
struct CameraDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Phone "screen"
                RoundedRectangle(cornerRadius: 30).fill(Color.black)
                RoundedRectangle(cornerRadius: 30).strokeBorder(Palette.hairline, lineWidth: 1)

                // Dynamic island hint
                Capsule().fill(Color.white.opacity(0.18))
                    .frame(width: w * 0.22, height: h * 0.028)
                    .position(x: w * 0.5, y: h * 0.055)

                // Crop window
                Rectangle().stroke(.white.opacity(0.45), lineWidth: 1)
                    .frame(width: w * 0.78, height: h * 0.46)
                    .position(x: w * 0.5, y: h * 0.42)

                // Top-left Type pill
                miniPill(w: w * 0.30, h: h * 0.045).position(x: w * 0.27, y: h * 0.135)
                // Top-right action pill
                miniPill(w: w * 0.30, h: h * 0.045).position(x: w * 0.73, y: h * 0.135)

                // Zoom pill on the crop edge
                Capsule().fill(Color.white.opacity(0.16))
                    .frame(width: w * 0.26, height: h * 0.032)
                    .position(x: w * 0.5, y: h * 0.62)

                // Shutter
                Circle().stroke(.white, lineWidth: 3)
                    .frame(width: w * 0.17, height: w * 0.17)
                    .position(x: w * 0.5, y: h * 0.78)
                // Gallery thumb
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.3))
                    .frame(width: w * 0.12, height: w * 0.12)
                    .position(x: w * 0.16, y: h * 0.78)
                // Flip
                Circle().fill(Color.white.opacity(0.2))
                    .frame(width: w * 0.12, height: w * 0.12)
                    .position(x: w * 0.84, y: h * 0.78)
                // Mode toggle
                Text("REFERENCE · PROJECT")
                    .font(.system(size: 7, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(.white.opacity(0.7))
                    .position(x: w * 0.5, y: h * 0.89)

                // Numbered badges (offset so they don't hide the control)
                badge(1, Palette.coral).position(x: w * 0.27, y: h * 0.205)
                badge(2, Palette.mint).position(x: w * 0.73, y: h * 0.205)
                badge(3, Palette.lemon).position(x: w * 0.665, y: h * 0.78)
                badge(4, Palette.coral).position(x: w * 0.16, y: h * 0.70)
                badge(5, Palette.mint).position(x: w * 0.5, y: h * 0.955)
                badge(6, Palette.lemon).position(x: w * 0.84, y: h * 0.70)
            }
        }
        .aspectRatio(0.52, contentMode: .fit)
    }

    private func miniPill(w: CGFloat, h: CGFloat) -> some View {
        Capsule().fill(Color.white.opacity(0.16)).frame(width: w, height: h)
    }

    private func badge(_ n: Int, _ tint: Color) -> some View {
        Text("\(n)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 19, height: 19)
            .background(Circle().fill(tint))
            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 0.5))
    }
}
