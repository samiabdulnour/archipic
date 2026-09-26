import SwiftUI
import UIKit

/// The warm limestone/ink palette ported from the web app, with light/dark
/// flips. Coral is the accent; mint = Reference mode, lemon = Project mode.
enum Palette {
    static let paper     = dyn(light: 0xF0EFE9, dark: 0x16140F)   // app background
    static let paperElev = dyn(light: 0xFFFFFF, dark: 0x25221E)   // cards, inputs
    static let tile      = dyn(light: 0xE5E3DA, dark: 0x1F1D17)   // swatch tiles
    static let ink       = dyn(light: 0x16140F, dark: 0xF0EFE9)   // primary text/art
    static let ink2      = dyn(light: 0x3A352B, dark: 0xBFB7A8)   // secondary text
    static let ink3      = dyn(light: 0x6E6657, dark: 0x8E867A)   // captions
    static let hairline  = dyn(light: 0x16140F, dark: 0xF0EFE9, alpha: 0.18)

    static let coral = Color(hex: "F44E48")   // accent / save / danger
    static let mint  = Color(hex: "7CE3A0")   // Reference mode
    static let lemon = Color(hex: "E8E373")   // Project mode

    private static func dyn(light: Int, dark: Int, alpha: CGFloat = 1) -> Color {
        Color(UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
        })
    }
}

extension UIColor {
    convenience init(rgb: Int, alpha: CGFloat = 1) {
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue:  CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}
