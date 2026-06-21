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

                ForEach(CameraGuide.steps) { step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(step.n)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(step.tint))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title).font(.headline)
                            Text(step.body).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.tile))
                }
            }
            .padding(16)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("How to use")
        .navigationBarTitleDisplayMode(.inline)
    }
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
