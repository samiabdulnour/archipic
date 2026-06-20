import SwiftUI

/// Film-simulation picker as a horizontal **name wheel** above the shutter —
/// like a camera mode dial. Tap a name to jump to it, or swipe to rotate; the
/// centred name is selected. Names only, no thumbnails. Less is more.
struct LooksWheel: View {
    @Bindable var camera: CameraController
    @State private var centered: CameraLook?

    private let itemWidth: CGFloat = 132
    private let hitHeight: CGFloat = 46     // tall, finger-friendly tap target

    var body: some View {
        VStack(spacing: 7) {
            wheel
            // One-line description of the centred look.
            Text(centered?.blurb ?? " ")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 300, minHeight: 28, alignment: .top)
                .id(centered)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: centered)
        }
    }

    private var wheel: some View {
        GeometryReader { geo in
            let side = max(0, (geo.size.width - itemWidth) / 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(CameraLook.allCases) { look in
                        let on = centered == look
                        Text(look.rawValue.uppercased())
                            .font(.system(size: 11, weight: on ? .semibold : .regular))
                            .tracking(1.4)
                            .foregroundStyle(on ? Palette.lemon : .white.opacity(0.5))
                            // Visible text stays small, but the whole 132×46 slot
                            // is tappable so a fingertip can't miss between names.
                            .frame(width: itemWidth, height: hitHeight)
                            .contentShape(Rectangle())
                            .id(look)
                            // Tap any name to centre + select it — no need to nudge
                            // the swipe just right.
                            .onTapGesture {
                                withAnimation(.snappy(duration: 0.28)) { centered = look }
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            .contentMargins(.horizontal, side, for: .scrollContent)
            .onAppear { centered = camera.colorLook }
            .onChange(of: centered) { _, v in
                guard let v, v != camera.colorLook else { return }
                camera.setColorLook(v)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .frame(height: hitHeight)
    }
}
