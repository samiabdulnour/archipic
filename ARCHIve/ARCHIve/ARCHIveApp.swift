import SwiftUI
import SwiftData
import UIKit

@main
struct ARCHIveApp: App {
    // SwiftData container holding the photo archive, mirrored to the user's
    // private iCloud (CloudKit) so it syncs across their devices and is backed
    // up automatically.
    let container: ModelContainer

    init() {
        Self.configureSegmentedAppearance()
        do {
            let config = ModelConfiguration(cloudKitDatabase: .automatic)
            container = try ModelContainer(for: Photo.self, Board.self, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    /// Unify the native segmented controls (the gallery lens / Reference filter
    /// toggles) with the tagging toggles: a lemon selected segment + dark text,
    /// echoing the lemon selection pill used when tagging. Keeps the Apple
    /// segmented shape, just in the app's accent so the whole app reads as one.
    private static func configureSegmentedAppearance() {
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = UIColor(Palette.lemon)
        seg.setTitleTextAttributes([
            .foregroundColor: UIColor(white: 0.13, alpha: 1),
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        ], for: .selected)
        seg.setTitleTextAttributes([
            .foregroundColor: UIColor(Palette.ink),
        ], for: .normal)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
