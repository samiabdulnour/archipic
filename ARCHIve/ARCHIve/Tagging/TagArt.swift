import SwiftUI

/// Native ports of the old web app's illustrated tag art — hand-drawn,
/// architectural line-work and edge-to-edge material hatches — so the tag
/// choices regain their graphic character while keeping the app's clean tiles.

// MARK: - Materiality hatch patterns

/// The eight Materiality textures, drawn as repeating unit cells that run
/// edge-to-edge (matching the web `.sw-art--pattern`). Ported cell-for-cell
/// from the web SVG `<pattern>` definitions.
struct MaterialityPattern: View {
    let id: String          // "Concrete", "Brick", ...
    var ink: Color

    var body: some View {
        Canvas { ctx, size in
            switch id {
            case "Concrete": dots(ctx, size, cell: 6, [(1.5, 1.5, 0.8), (4.5, 3.5, 0.7), (2.2, 4.8, 0.55)])
            case "Stone":    dots(ctx, size, cell: 18, [(3,4,0.6),(10,3,0.55),(14,9,0.65),(6,12,0.6),(12,15,0.55),(2,16,0.6)])
            case "Plaster":  dots(ctx, size, cell: 14, [(3,3,0.7),(9,6,0.6),(5,10,0.6),(11,11,0.7)])
            case "Earth":    dots(ctx, size, cell: 5, [(1,1,0.5),(3,2,0.45),(2,4,0.5),(4,3.5,0.4)])
            case "Brick":    brick(ctx, size)
            case "Timber":   timber(ctx, size)
            case "Metal":    metal(ctx, size)
            case "Glass":    glass(ctx, size)
            case "Tile":     gridPattern(ctx, size)
            default:         questionMark(ctx, size)   // "Other"
            }
        }
    }

    private func gridPattern(_ ctx: GraphicsContext, _ size: CGSize) {
        var p = Path()
        var x: CGFloat = 0
        while x <= size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += 8 }
        var y: CGFloat = 0
        while y <= size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += 8 }
        ctx.stroke(p, with: .color(ink), lineWidth: 0.9)
    }

    /// Tile a filled-dot cell across the whole area.
    private func dots(_ ctx: GraphicsContext, _ size: CGSize, cell: CGFloat,
                      _ pts: [(CGFloat, CGFloat, CGFloat)]) {
        tile(size, cell: cell) { ox, oy in
            for p in pts {
                let r = p.2
                let rect = CGRect(x: ox + p.0 - r, y: oy + p.1 - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(ink))
            }
        }
    }

    private func brick(_ ctx: GraphicsContext, _ size: CGSize) {
        tile(size, cell: CGSize(width: 14, height: 8)) { ox, oy in
            for r in [CGRect(x: 0, y: 0, width: 13, height: 3),
                      CGRect(x: -7, y: 4, width: 13, height: 3),
                      CGRect(x: 7, y: 4, width: 13, height: 3)] {
                let rr = CGRect(x: ox + r.minX, y: oy + r.minY, width: r.width, height: r.height)
                ctx.stroke(Path(rr), with: .color(ink), lineWidth: 0.9)
            }
        }
    }

    private func timber(_ ctx: GraphicsContext, _ size: CGSize) {
        tile(size, cell: CGSize(width: 20, height: 6)) { ox, oy in
            var top = Path()
            top.move(to: CGPoint(x: ox, y: oy + 2))
            top.addQuadCurve(to: CGPoint(x: ox + 10, y: oy + 2), control: CGPoint(x: ox + 5, y: oy + 1))
            top.addQuadCurve(to: CGPoint(x: ox + 20, y: oy + 2), control: CGPoint(x: ox + 15, y: oy + 3))
            ctx.stroke(top, with: .color(ink), lineWidth: 0.9)
            var bot = Path()
            bot.move(to: CGPoint(x: ox, y: oy + 4))
            bot.addQuadCurve(to: CGPoint(x: ox + 10, y: oy + 4), control: CGPoint(x: ox + 5, y: oy + 5))
            bot.addQuadCurve(to: CGPoint(x: ox + 20, y: oy + 4), control: CGPoint(x: ox + 15, y: oy + 3))
            ctx.stroke(bot, with: .color(ink), lineWidth: 0.7)
        }
    }

    private func metal(_ ctx: GraphicsContext, _ size: CGSize) {
        tile(size, cell: 6) { ox, oy in
            var p = Path()
            p.move(to: CGPoint(x: ox, y: oy));       p.addLine(to: CGPoint(x: ox + 6, y: oy + 6))
            p.move(to: CGPoint(x: ox + 6, y: oy));    p.addLine(to: CGPoint(x: ox, y: oy + 6))
            ctx.stroke(p, with: .color(ink), lineWidth: 0.9)
        }
    }

    private func glass(_ ctx: GraphicsContext, _ size: CGSize) {
        tile(size, cell: 10) { ox, oy in
            var p = Path()
            p.move(to: CGPoint(x: ox, y: oy + 2)); p.addLine(to: CGPoint(x: ox + 10, y: oy + 2))
            p.move(to: CGPoint(x: ox, y: oy + 6)); p.addLine(to: CGPoint(x: ox + 10, y: oy + 6))
            ctx.stroke(p, with: .color(ink), lineWidth: 0.9)
        }
    }

    private func questionMark(_ ctx: GraphicsContext, _ size: CGSize) {
        let text = ctx.resolve(Text("?").font(.system(size: size.height * 0.5, weight: .semibold)).foregroundStyle(ink))
        ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    /// Repeat `body` over a square unit cell across the whole canvas.
    private func tile(_ size: CGSize, cell: CGFloat, _ body: (CGFloat, CGFloat) -> Void) {
        tile(size, cell: CGSize(width: cell, height: cell), body)
    }
    private func tile(_ size: CGSize, cell: CGSize, _ body: (CGFloat, CGFloat) -> Void) {
        var y = -cell.height
        while y < size.height + cell.height {
            var x = -cell.width
            while x < size.width + cell.width {
                body(x, y)
                x += cell.width
            }
            y += cell.height
        }
    }
}

// MARK: - Reusable illustrated tile

/// A selectable tile that shows artwork in a square panel with a label below
/// and a corner check when selected — the old swatch idiom, in the app's
/// rounded style with the indigo accent.
struct IllustratedTile<Art: View>: View {
    let label: String
    let selected: Bool
    /// Line-art glyphs are inset (~62% like the web swatches); patterns and
    /// colour swatches fill the tile edge-to-edge.
    var fullBleed: Bool = false
    let art: Art
    let action: () -> Void

    init(label: String, selected: Bool, fullBleed: Bool = false,
         @ViewBuilder art: () -> Art, action: @escaping () -> Void) {
        self.label = label
        self.selected = selected
        self.fullBleed = fullBleed
        self.art = art()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Palette.tile)
                        .overlay(art.padding(fullBleed ? 3 : 15).clipShape(RoundedRectangle(cornerRadius: 9)))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(selected ? Palette.coral : Palette.hairline,
                                          lineWidth: selected ? 2 : 0.5))
                        .aspectRatio(1, contentMode: .fit)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.coral, Palette.paperElev)
                            .padding(5)
                    }
                }
                Text(label)
                    .font(.caption2)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
                    .foregroundStyle(selected ? Palette.coral : Palette.ink2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact tile (label inside the button)

/// A small selectable tile with the artwork on top and the name *inside* the
/// button — denser than IllustratedTile, for fitting more options per screen.
struct CompactTile<Art: View>: View {
    let label: String
    let selected: Bool
    let art: Art
    let action: () -> Void

    init(label: String, selected: Bool, @ViewBuilder art: () -> Art, action: @escaping () -> Void) {
        self.label = label
        self.selected = selected
        self.art = art()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                art.frame(width: 26, height: 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)   // centre in the space above the label
                Text(label)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    .frame(height: 24, alignment: .top)
            }
            .padding(.top, 9).padding(.bottom, 6).padding(.horizontal, 3)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            // App Store-style: no box on unselected (icon + label only); the selected
            // tile gets a soft coral highlight + tinted content. No hard border.
            .background(RoundedRectangle(cornerRadius: 13)
                .fill(selected ? Palette.coral.opacity(0.16) : .clear))
            .foregroundStyle(selected ? Palette.coral : Palette.ink)
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .animation(.easeOut(duration: 0.15), value: selected)
        }
        .buttonStyle(.plain)
    }
}
