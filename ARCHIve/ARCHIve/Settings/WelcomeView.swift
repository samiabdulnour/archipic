import SwiftUI

/// First-run welcome / about screen — app identity, a short lede, and the
/// camera-layout legend, mirroring the web app's welcome page.
struct WelcomeView: View {
    var onGetStarted: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    (Text("Archi").foregroundStyle(Palette.ink)
                     + Text(".vé").foregroundStyle(Palette.coral))
                        .font(.system(size: 42, weight: .bold, design: .serif))
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
        .init(n: 1, title: "Type", tint: Palette.coral,
              body: "Top-left: Building · Element · Graphic. Tap to set what you're capturing; it pre-fills the tag."),
        .init(n: 2, title: "Tag · Reuse · More", tint: Palette.mint,
              body: "Top-right. The tag icon toggles Lite ↔ Full; Reuse applies your last photo's tags; the dots open camera settings."),
        .init(n: 3, title: "Shutter", tint: Palette.lemon,
              body: "Tap to capture. Full opens tagging right after; Lite saves instantly to tag later."),
        .init(n: 4, title: "Gallery", tint: Palette.coral,
              body: "Bottom-left shows your latest photo — tap to jump into the archive."),
        .init(n: 5, title: "Reference vs Project", tint: Palette.mint,
              body: "Reference for things found out there; Project for a site shoot — pick the project once, shoot a sequence."),
        .init(n: 6, title: "Flip camera", tint: Palette.lemon,
              body: "Bottom-right — switch between the rear and front cameras."),
    ]
}
