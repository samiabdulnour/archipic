import SwiftUI
import SwiftData
import Foundation
import UIKit

/// App-wide orientation policy. iPad reviews and composes in any orientation,
/// but the camera is a portrait-only viewfinder (its AVFoundation connections
/// are locked to portrait), so it pins the whole app to portrait while it's on
/// screen. iPhone stays portrait everywhere.
enum AppOrientation {
    /// Set while the camera is presented (see CameraView). Read on the main
    /// thread by UIKit via AppDelegate; no cross-thread access.
    static var cameraActive = false
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if AppOrientation.cameraActive { return .portrait }
        return UIDevice.current.userInterfaceIdiom == .pad ? .allButUpsideDown : .portrait
    }
}

@main
struct ARCHIveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // SwiftData container holding the photo archive, mirrored to the user's
    // private iCloud (CloudKit) so it syncs across their devices and is backed
    // up automatically.
    let container: ModelContainer

    init() {
        do {
            container = try Self.makeContainer()
        } catch {
            // The local store failed to open — e.g. corrupted by a mid-write OOM
            // kill, or a migration error. Move it ASIDE (never delete) and retry
            // once; CloudKit re-syncs the archive into the fresh store. This
            // avoids a permanent launch crash-loop that would lock the owner out
            // of their archive (and of Settings → Export).
            Self.moveStoreAside()
            do {
                container = try Self.makeContainer()
            } catch {
                fatalError("Could not create ModelContainer after recovery: \(error)")
            }
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        return try ModelContainer(for: Photo.self, Board.self, configurations: config)
    }

    /// Rename the default SwiftData store (and its -wal/-shm sidecars) to a
    /// timestamped `.corrupt-<n>` so a fresh store can open. Kept, not deleted,
    /// so the bytes remain available for manual recovery.
    private static func moveStoreAside() {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: false) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let src = support.appendingPathComponent("default.store\(suffix)")
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = support.appendingPathComponent("default.store\(suffix).corrupt-\(stamp)")
            try? fm.moveItem(at: src, to: dst)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
