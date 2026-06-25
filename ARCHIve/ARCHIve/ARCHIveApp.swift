import SwiftUI
import SwiftData

@main
struct ARCHIveApp: App {
    // SwiftData container holding the photo archive, mirrored to the user's
    // private iCloud (CloudKit) so it syncs across their devices and is backed
    // up automatically.
    let container: ModelContainer

    init() {
        do {
            let config = ModelConfiguration(cloudKitDatabase: .automatic)
            container = try ModelContainer(for: Photo.self, Board.self, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
