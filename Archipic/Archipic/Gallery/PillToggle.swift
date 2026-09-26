import SwiftUI

/// One option in a `PillToggle`.
struct PillOption<T: Hashable>: Identifiable {
    let value: T
    let label: String
    var symbol: String? = nil
    var id: T { value }
}

/// A row of pill buttons for picking one option — the app's unified toggle, in
/// the same lemon-pill language as the tagging type picker (boxless, the selected
/// one a lemon pill). Used instead of a native segmented control: its sliding
/// selection doesn't animate cleanly with a custom (lemon) tint under Liquid
/// Glass, whereas these buttons cross-fade smoothly and we control the look.
struct PillToggle<T: Hashable>: View {
    @Binding var selection: T
    let options: [PillOption<T>]
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { opt in
                let on = selection == opt.value
                Button { selection = opt.value } label: {
                    HStack(spacing: 6) {
                        if let s = opt.symbol {
                            Image(systemName: s).font(.system(size: 14)).symbolVariant(.fill)
                        }
                        Text(opt.label).font(.system(size: 14, weight: on ? .semibold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity).frame(height: height)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(on ? Palette.lemon : .clear))
                    .foregroundStyle(on ? Color(white: 0.13) : Palette.ink)
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}
