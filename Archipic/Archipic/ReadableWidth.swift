import SwiftUI

extension View {
    /// Constrain content to a comfortable reading / interaction width and centre
    /// it, so full-screen and pushed views don't stretch edge-to-edge on iPad.
    ///
    /// A no-op on iPhone: the screen is already narrower than `max`, so the cap
    /// never bites and the layout is byte-for-byte what it was.
    func readableWidth(_ max: CGFloat = 720) -> some View {
        frame(maxWidth: max).frame(maxWidth: .infinity)
    }
}
