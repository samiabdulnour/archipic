import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var photos: [Photo]
    @State private var showCamera = false
    @State private var didAutoOpen = false
    @State private var lens: GalleryLens = .time   // lifted here so an iPad sidebar can drive it
    @State private var pendingProject: String?    // carried from a Shortcuts/Siri capture request
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var hSize
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("welcomed") private var welcomed = false
    @AppStorage("launchScreen") private var launchScreen = "camera"   // camera | gallery

    var body: some View {
        Group {
            if hSize == .regular {
                // iPad: lenses live in a sidebar, the grid fills the detail pane.
                NavigationSplitView {
                    lensSidebar
                } detail: {
                    galleryStack(showsLensPicker: false)
                }
            } else {
                // iPhone (compact): unchanged — the in-view lens picker sits atop
                // the grid in a single navigation stack.
                galleryStack(showsLensPicker: true)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(initialProject: pendingProject)
        }
        .fullScreenCover(isPresented: Binding(get: { !welcomed }, set: { welcomed = !$0 })) {
            WelcomeView { welcomed = true; showCamera = true }
        }
        // Drive appearance at the window level so it applies everywhere —
        // including sheets — and Auto cleanly reverts to the system setting
        // (preferredColorScheme(nil) doesn't reliably clear on a sheet).
        .onAppear {
            Settings.applyAppearance(appearance)
            ReviewPrompt.noteFirstUseIfNeeded()
            ShareInbox.drain(into: modelContext)   // import anything shared while we were away
            if let request = QuickCapture.consumeCameraRequest() {
                pendingProject = request.project; showCamera = true
            }
        }
        // Lock Screen control / widget tapped while the app was already running:
        // open the camera when we come back to the foreground. Also drain the
        // Share extension's inbox (the user may have shared into it meanwhile).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            ShareInbox.drain(into: modelContext)
            if let request = QuickCapture.consumeCameraRequest() {
                pendingProject = request.project; showCamera = true
            }
        }
        .onChange(of: appearance) { _, newValue in Settings.applyAppearance(newValue) }
    }

    /// The gallery in its own navigation stack, with the camera button and the
    /// destination wired. Shared by the compact (iPhone) and iPad-detail paths.
    @ViewBuilder
    private func galleryStack(showsLensPicker: Bool) -> some View {
        NavigationStack {
            GalleryView(lens: $lens, showsLensPicker: showsLensPicker)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                // Navigate on the id String, not the live Photo — so re-evaluating
                // the destination never reads a deleted model (an uncatchable trap).
                .navigationDestination(for: String.self) { id in
                    PhotoDetailView(photoID: id)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showCamera = true } label: {
                            Image(systemName: "camera.fill")
                        }
                    }
                    #if targetEnvironment(simulator)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Seed") { seedSample() }
                    }
                    #endif
                }
                // Launch into capture or the gallery per the user's preference
                // (once per launch), after they've seen the welcome screen.
                .onAppear {
                    if !didAutoOpen && welcomed {
                        didAutoOpen = true
                        if launchScreen == "camera" { showCamera = true }
                    }
                }
        }
    }

    /// iPad sidebar: the four lenses, natively highlighted, driving `lens`.
    private var lensSidebar: some View {
        List(selection: Binding(get: { Optional(lens) },
                                set: { if let v = $0 { lens = v } })) {
            ForEach(GalleryLens.allCases) { l in
                Label(l.rawValue, systemImage: l.symbol).tag(l)
            }
        }
        .navigationTitle("Archipic")
        .listStyle(.sidebar)
    }

    #if targetEnvironment(simulator)
    /// Inserts a few synthetic photos so the gallery / tagging / detail flows
    /// can be exercised on the simulator, which has no camera. Never compiled
    /// into a device build.
    private func seedSample() {
        let palette: [(UIColor, HumanTags, String?)] = [
            (.systemTeal,   buildingTags(),  "Aalto House"),
            (.systemBrown,  elementTags(),   nil),
            (.systemIndigo, graphicTags(),   "Aalto House"),
            (.systemGreen,  buildingTags(),  nil),
        ]
        for (i, item) in palette.enumerated() {
            guard let data = swatch(item.0) else { continue }
            let p = Photo(imageData: data,
                          createdAt: Date().addingTimeInterval(Double(-i) * 3600),
                          latitude: 60.20 + Double(i) * 0.01,
                          longitude: 24.86 + Double(i) * 0.01,
                          humanTags: item.1,
                          project: item.2)
            modelContext.insert(p)
        }
        try? modelContext.save()
    }

    private func buildingTags() -> HumanTags {
        var t = HumanTags(); t.type = "building"; t.typology = "Residential"
        t.room = "living"; t.concepts = ["light", "space"]; t.materials = ["Timber", "Glass"]
        t.authorYear = "Aalto, 1939"; return t
    }
    private func elementTags() -> HumanTags {
        var t = HumanTags(); t.type = "element"; t.element = "Stair"; t.materials = ["Concrete"]; return t
    }
    private func graphicTags() -> HumanTags {
        var t = HumanTags(); t.type = "graphic"; t.graphicKind = "drawing"; t.visual = ["Monochrome", "Minimal"]; return t
    }

    private func swatch(_ color: UIColor) -> Data? {
        let size = CGSize(width: 800, height: 1000)
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.8)
    }
    #endif
}

#Preview {
    ContentView()
        .modelContainer(for: Photo.self, inMemory: true)
}
