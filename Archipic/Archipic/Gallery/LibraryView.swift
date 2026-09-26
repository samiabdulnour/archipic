import SwiftUI
import SwiftData
import Photos

/// Browse the system Photos library and tag photos *in place* — the app stores a
/// reference (the asset's id) plus your tags, with **no copy**. Already-tagged
/// photos show a check; tapping one re-opens its tags.
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allPhotos: [Photo]

    @State private var status: PHAuthorizationStatus = PhotosLibrary.status
    @State private var assets: [PHAsset] = []
    @State private var tagTarget: Photo?
    @State private var batchTargets: [Photo] = []
    @State private var sequentialQueue: [Photo] = []   // "one by one" run
    @State private var columns = 3                  // grid density; pinch to change
    @State private var selecting = false
    @State private var selected: Set<String> = []   // asset localIdentifiers
    /// Ids of references this presentation just CREATED — the only ones the
    /// skip-cleanup may remove. Pre-existing untagged references (left by an
    /// interrupted earlier session, or arriving from another device via CloudKit)
    /// must never be auto-deleted.
    @State private var sessionRefs: Set<String> = []

    private var authorized: Bool { status == .authorized || status == .limited }

    private var cols: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: columns)
    }

    private var referenced: [String: Photo] {
        var m: [String: Photo] = [:]
        for p in allPhotos { if let id = p.assetLocalID, !id.isEmpty { m[id] = p } }
        return m
    }

    var body: some View {
        NavigationStack {
            Group {
                switch status {
                case .authorized, .limited: grid
                case .denied, .restricted:  deniedView
                default: ProgressView()
                }
            }
            .navigationTitle(selecting ? "\(selected.count) selected" : "Tag from Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if authorized {
                        Button(selecting ? "Cancel" : "Select") {
                            withAnimation { selecting.toggle(); selected.removeAll() }
                        }
                    }
                }
                // "Done" closes the picker — only show it while *browsing*. During
                // multi-select it read as "save my selection" (it doesn't — it just
                // discards and closes), so hide it. The bottom bar holds the real
                // actions (Add / One by one / Same tag); "Cancel" backs out.
                if !selecting {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
            .background(Palette.paper.ignoresSafeArea())
        }
        .task { await loadAssets() }
        .fullScreenCover(item: $tagTarget, onDismiss: endTagging) { photo in
            TagSheetView(photo: photo,
                         batchPhotos: batchTargets.count > 1 ? batchTargets : nil) { tagTarget = nil }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !sequentialQueue.isEmpty },
            set: { if !$0 { sequentialQueue = [] } }
        ), onDismiss: endTagging) {
            SequentialTagView(queue: sequentialQueue) { sequentialQueue = [] }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    let existing = referenced[asset.localIdentifier]
                    Button { tapCell(asset, existing: existing) } label: {
                        LibraryCell(asset: asset, tagged: existing != nil,
                                    selecting: selecting,
                                    selected: selected.contains(asset.localIdentifier))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .animation(.snappy(duration: 0.25), value: columns)
        }
        .simultaneousGesture(zoomGesture)
    }

    /// Pinch to change grid density (zoom out → more photos per screen).
    private var zoomGesture: some Gesture {
        MagnifyGesture().onEnded { v in
            withAnimation(.snappy(duration: 0.25)) {
                if v.magnification > 1.15 { columns = max(2, columns - 1) }
                else if v.magnification < 0.85 { columns = min(7, columns + 1) }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 7) {
            Button("Clear") { selected.removeAll() }
                .font(.subheadline)
                .disabled(selected.isEmpty)
                .foregroundStyle(selected.isEmpty ? Palette.ink3 : Palette.ink2)
            Spacer(minLength: 6)
            // Add to the archive without tagging now (tag later from the gallery).
            actionButton("Add") { addUntagged() }
            // One by one: step through each, with "use previous" for fast cleaning.
            actionButton("One by one") { startSequential() }
            // Same tag applied to all selected at once.
            actionButton("Same tag") { startBatchTagging() }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// The selection actions, all one consistent style (no odd red/white mismatch).
    private func actionButton(_ title: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(Capsule().fill(Palette.tile))
                .foregroundStyle(selected.isEmpty ? Palette.ink3 : Palette.ink)
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
    }

    private var deniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle).foregroundStyle(Palette.ink3)
            Text("Photos access is off").font(.headline)
            Text("Allow photo access to tag your existing library.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Settings") {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            .buttonStyle(.borderedProminent).tint(Palette.coral)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadAssets() async {
        if status == .notDetermined { status = await PhotosLibrary.requestAuthorization() }
        guard status == .authorized || status == .limited else { return }
        let result = PhotosLibrary.fetchImages()
        var arr: [PHAsset] = []
        arr.reserveCapacity(result.count)
        result.enumerateObjects { a, _, _ in arr.append(a) }
        assets = arr
    }

    private func tapCell(_ asset: PHAsset, existing: Photo?) {
        if selecting {
            let id = asset.localIdentifier
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        } else {
            tap(asset, existing: existing)
        }
    }

    private func tap(_ asset: PHAsset, existing: Photo?) {
        batchTargets = []
        if let existing { tagTarget = existing; return }
        let photo = makeReference(for: asset)
        modelContext.insert(photo)
        sessionRefs.insert(photo.id)
        tagTarget = photo
    }

    /// Build a Photo reference for each selected asset (reusing any already
    /// referenced), in the on-screen order.
    private func buildTargets() -> [Photo] {
        var targets: [Photo] = []
        for asset in assets where selected.contains(asset.localIdentifier) {
            if let existing = referenced[asset.localIdentifier] {
                targets.append(existing)
            } else {
                let p = makeReference(for: asset)
                modelContext.insert(p)
                sessionRefs.insert(p.id)
                targets.append(p)
            }
        }
        return targets
    }

    /// Add the selected photos to the archive *untagged* (tag later from the
    /// gallery). Marked with `importedAt` so the skip-cleanup spares them.
    private func addUntagged() {
        let targets = buildTargets()
        for p in targets where p.importedAt == nil { p.importedAt = Date() }
        try? modelContext.save()
        selected.removeAll()
        dismiss()
    }

    /// Same tag → all selected at once.
    private func startBatchTagging() {
        let targets = buildTargets()
        guard let first = targets.first else { return }
        batchTargets = targets
        tagTarget = first
    }

    /// One by one → step through each selected photo.
    private func startSequential() {
        let targets = buildTargets()
        guard !targets.isEmpty else { return }
        sequentialQueue = targets
    }

    private func makeReference(for asset: PHAsset) -> Photo {
        Photo(imageData: Data(),
              createdAt: asset.creationDate ?? .now,
              latitude: asset.location?.coordinate.latitude,
              longitude: asset.location?.coordinate.longitude,
              assetLocalID: asset.localIdentifier)
    }

    private func endTagging() {
        cleanupIfSkipped()
        sessionRefs.removeAll()
        batchTargets = []
        if selecting { withAnimation { selecting = false; selected.removeAll() } }
    }

    /// A reference THIS session just created and the user then skipped (left
    /// untagged, not "Added") means it was unwanted — drop it. Scoped to
    /// `sessionRefs` so it can only ever remove a reference created in this
    /// presentation; pre-existing untagged references, camera shots, and photos
    /// explicitly "Added" (importedAt set) are never auto-removed.
    private func cleanupIfSkipped() {
        for p in allPhotos where sessionRefs.contains(p.id)
            && p.isReference && p.isUntagged && !p.isCameraShot && p.importedAt == nil {
            modelContext.delete(p)
        }
        try? modelContext.save()
    }
}

private struct LibraryCell: View {
    let asset: PHAsset
    let tagged: Bool
    var selecting: Bool = false
    var selected: Bool = false
    @State private var image: UIImage?

    var body: some View {
        // Color.clear forces a square sized to the cell width; the image fills it
        // and is clipped — a definite frame, so thumbnails never overflow.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    Palette.tile
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if tagged {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Palette.coral)
                        .padding(4).shadow(radius: 1)
                }
            }
            .overlay {
                if selecting {
                    ZStack(alignment: .bottomLeading) {
                        Color.black.opacity(selected ? 0.3 : 0)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selected ? .white : .white.opacity(0.9),
                                             selected ? Palette.coral : .clear)
                            .padding(5).shadow(radius: 1)
                    }
                }
            }
            .overlay {
                if selecting && selected {
                    Rectangle().strokeBorder(Palette.coral, lineWidth: 2)
                }
            }
            .task(id: asset.localIdentifier) {
                if image == nil { image = await PhotosLibrary.image(asset: asset, maxPixel: 400) }
            }
    }
}
