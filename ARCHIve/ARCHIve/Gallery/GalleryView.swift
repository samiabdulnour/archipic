import SwiftUI
import SwiftData
import MapKit
import PhotosUI
import ImageIO

enum GalleryLens: String, CaseIterable, Identifiable {
    case time = "Time", reference = "Reference", project = "Project", map = "Map"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .time: return "clock"
        case .reference: return "square.grid.2x2"
        case .project: return "folder"
        case .map: return "map"
        }
    }
}

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Photo.createdAt, order: .reverse) private var photos: [Photo]

    @State private var lens: GalleryLens = .time
    @State private var search = ""

    // Filters
    @State private var showFilter = false
    @State private var filterType: String?     // nil | "untagged" | building | element | graphic
    @State private var filterTypology: String? // e.g. "Civic" (building typology)
    @State private var filterMaterial: String? // e.g. "Brick"
    @State private var filterYear = 0          // 0 = any (capture year)
    @State private var filterProject: String?
    @State private var filterFavorites = false
    @State private var filterMinRating = 0     // 0 = any

    // Selection
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var confirmDelete = false
    @State private var shareItems: [UIImage] = []
    @State private var showShare = false
    @State private var composerPhotos: [Photo] = []   // selection to compose into a board
    @State private var showComposer = false
    @State private var showBoards = false             // saved-boards shelf
    // drag-to-paint selection
    @State private var gridWidth: CGFloat = 0
    @State private var dragMode: Bool? = nil          // true = selecting, false = deselecting
    @State private var dragPainted: Set<String> = []
    @State private var dragAxis: Bool? = nil          // true = horizontal (paint), false = vertical (scroll)

    // Import

    // Settings
    @State private var showSettings = false

    // Tag from existing Photos library
    @State private var showLibrary = false

    // Single-photo context-menu actions
    @State private var editTarget: Photo?
    @State private var photoToDelete: Photo?
    /// Shared tag clipboard (same key as the detail view) for copy/paste tags.
    @AppStorage(TagClipboard.key) private var copiedTagsJSON = ""

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    // Time-grid zoom: pinch to change how many photos per row (1...5).
    @State private var gridCols = 3
    @State private var pinchBaseCols: Int?

    // MARK: Derived

    private var filtersActive: Bool {
        filterType != nil || filterTypology != nil || filterMaterial != nil || filterYear > 0
            || filterProject != nil || filterFavorites || filterMinRating > 0
    }

    private var filtered: [Photo] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        let cal = Calendar.current
        return photos.filter { p in
            if filterFavorites && !p.isFavorite { return false }
            if filterMinRating > 0 && (p.humanTags.rating ?? 0) < filterMinRating { return false }
            if !words.isEmpty {
                let txt = p.searchText
                if !words.allSatisfy({ txt.contains($0) }) { return false }
            }
            if let ft = filterType {
                if ft == "untagged" { if !p.isUntagged { return false } }
                else if p.humanTags.type != ft { return false }
            }
            if let ty = filterTypology, p.humanTags.typology != ty { return false }
            if let mat = filterMaterial, !p.humanTags.materials.contains(mat) { return false }
            if filterYear > 0, cal.component(.year, from: p.createdAt) != filterYear { return false }
            if let fp = filterProject, p.project != fp { return false }
            return true
        }
    }

    private var projectNames: [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in photos { if let n = p.project, !n.isEmpty, seen.insert(n).inserted { out.append(n) } }
        return Set(out).union(Settings.customProjects).sorted()
    }

    /// Distinct typologies / materials / capture-years present in the archive, so
    /// the filter only offers values that actually match something.
    private var typologyNames: [String] {
        var s = Set<String>()
        for p in photos { if let t = p.humanTags.typology, !t.isEmpty { s.insert(t) } }
        return s.sorted()
    }
    private var materialNames: [String] {
        var s = Set<String>()
        for p in photos { for m in p.humanTags.materials where !m.isEmpty { s.insert(m) } }
        return s.sorted()
    }
    private var years: [Int] {
        let cal = Calendar.current
        return Set(photos.map { cal.component(.year, from: $0.createdAt) }).sorted(by: >)
    }

    var body: some View {
        VStack(spacing: 0) {
            lensPicker
            if photos.isEmpty {
                emptyState
            } else {
                if filtersActive || !search.isEmpty { resultBar }
                switch lens {
                case .time:      grid(filtered)
                // Reference is a browse-only row index; in Select mode show a flat
                // selectable grid instead (the row browser has no selection).
                case .reference: if selecting { grid(filtered) } else { referenceLens }
                case .project:   projectLens
                case .map:       MapLens(photos: filtered.filter { $0.latitude != nil }, selecting: false)
                }
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
        .toolbar { galleryToolbar }
        .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
        .sheet(isPresented: $showFilter) {
            FilterSheet(type: $filterType, typology: $filterTypology, material: $filterMaterial,
                        year: $filterYear, project: $filterProject,
                        favorites: $filterFavorites, minRating: $filterMinRating,
                        projects: projectNames, typologies: typologyNames,
                        materials: materialNames, years: years)
        }
        .confirmationDialog("Delete \(selected.count) photo\(selected.count == 1 ? "" : "s")?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This can't be undone.") }
        .sheet(isPresented: $showShare) { ActivityView(items: shareItems) }
        .sheet(isPresented: $showComposer) { BoardComposerView(photos: composerPhotos) }
        .sheet(isPresented: $showBoards) { BoardsListView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(item: $editTarget) { photo in
            TagSheetView(photo: photo) { editTarget = nil }
        }
        .fullScreenCover(isPresented: $showLibrary) { LibraryView() }
        .alert("Delete this photo?", isPresented: Binding(
            get: { photoToDelete != nil }, set: { if !$0 { photoToDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let p = photoToDelete { modelContext.delete(p); try? modelContext.save() }
                photoToDelete = nil
            }
            Button("Cancel", role: .cancel) { photoToDelete = nil }
        } message: { Text("This permanently removes the photo from your archive.") }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var galleryToolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { selecting = false; selected.removeAll() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "Deselect All" : "Select All") { toggleSelectAll() }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showFilter = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
                    Button { showLibrary = true } label: { Label("From Photos", systemImage: "photo.on.rectangle.angled") }
                    Button { selecting = true } label: { Label("Select", systemImage: "checkmark.circle") }
                    Button { showBoards = true } label: { Label("Boards", systemImage: "doc.richtext") }
                    Divider()
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    /// Photos actually shown in the current lens. Select-All must use this, not
    /// `filtered`, so it never selects (and then deletes) photos the lens hides —
    /// Map shows only located photos, Project only filed ones.
    private var visiblePhotos: [Photo] {
        switch lens {
        case .map:     return filtered.filter { $0.latitude != nil }
        case .project: return filtered.filter { !($0.project ?? "").isEmpty }
        default:       return filtered
        }
    }
    private var allSelected: Bool {
        !visiblePhotos.isEmpty && visiblePhotos.allSatisfy { selected.contains($0.id) }
    }
    private func toggleSelectAll() {
        let vis = visiblePhotos.map(\.id)
        if allSelected { vis.forEach { selected.remove($0) } } else { selected.formUnion(vis) }
    }

    // MARK: Lenses

    private var referenceLens: some View {
        ReferenceLens(photos: filtered, gridCols: $gridCols)
    }

    private var projectLens: some View {
        // Only photos that belong to a project (skip unfiled).
        let filed = filtered.filter { ($0.project ?? "").isEmpty == false }
        let groups = Dictionary(grouping: filed) { $0.project ?? "" }
        let keys = groups.keys.sorted()
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                ForEach(keys, id: \.self) { key in
                    Section {
                        LazyVGrid(columns: cols, spacing: 2) {
                            ForEach(groups[key] ?? []) { cell($0) }
                        }
                    } header: {
                        Text(key).font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Palette.paper)
                    }
                }
            }
        }
    }

    private func grid(_ items: [Photo]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: gridCols)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items) { cell($0) }
            }
            .animation(.easeInOut(duration: 0.2), value: gridCols)
            .background(GeometryReader { p in Color.clear
                .onAppear { gridWidth = p.size.width }
                .onChange(of: p.size.width) { _, w in gridWidth = w } })
            .coordinateSpace(name: "galgrid")
            // Drag horizontally across thumbnails to paint a selection; vertical
            // drags still scroll. The UIKit pan recognizer is told to coexist with
            // the scroll view's own pan, so scrolling keeps working. Select mode only.
            .paintSelectable(active: selecting,
                onChange: { loc, t in paintAt(loc, translation: t, items: items) },
                onEnd: endPaint)
        }
        // Pinch to change photos-per-row: spread = bigger/fewer, pinch = smaller/more.
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if pinchBaseCols == nil { pinchBaseCols = gridCols }
                    let base = pinchBaseCols ?? gridCols
                    let steps = Int((value.magnification - 1) * 5)
                    gridCols = min(8, max(1, base - steps))
                }
                .onEnded { _ in pinchBaseCols = nil }
        )
    }

    /// Paint one drag sample: decide the axis once (across = select, down = scroll),
    /// then for a horizontal drag mark the thumbnail under the finger.
    private func paintAt(_ location: CGPoint, translation: CGSize, items: [Photo]) {
        if dragAxis == nil {
            guard abs(translation.width) > 6 || abs(translation.height) > 6 else { return }
            dragAxis = abs(translation.width) >= abs(translation.height)
        }
        guard dragAxis == true, gridWidth > 0, gridCols > 0 else { return }
        let cw = (gridWidth - CGFloat(gridCols - 1) * 2) / CGFloat(gridCols)
        let step = cw + 2
        let col = Int(location.x / step), row = Int(location.y / step)
        guard col >= 0, col < gridCols, row >= 0 else { return }
        let idx = row * gridCols + col
        guard idx >= 0, idx < items.count else { return }
        let id = items[idx].id
        if dragMode == nil { dragMode = !selected.contains(id) }
        if !dragPainted.contains(id) {
            dragPainted.insert(id)
            if dragMode == true { selected.insert(id) } else { selected.remove(id) }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
    private func endPaint() { dragAxis = nil; dragMode = nil; dragPainted.removeAll() }

    // MARK: Cell + badges

    @ViewBuilder
    private func cell(_ photo: Photo) -> some View {
        if selecting {
            Button { toggleSelect(photo) } label: {
                tile(photo, selected: selected.contains(photo.id))
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: photo) { tile(photo, selected: false) }
                .buttonStyle(.plain)
                .contextMenu { photoMenu(photo) }
        }
    }

    /// Native-style long-press menu for a single photo.
    @ViewBuilder
    private func photoMenu(_ photo: Photo) -> some View {
        Button { toggleFavorite(photo) } label: {
            Label(photo.isFavorite ? "Remove Favourite" : "Favourite",
                  systemImage: photo.isFavorite ? "heart.slash" : "heart")
        }
        Button { editTarget = photo } label: { Label("Edit tags", systemImage: "tag") }
        Divider()
        Button { copyTags(photo) } label: { Label("Copy tags", systemImage: "doc.on.doc") }
            .disabled(photo.humanTags.isEmpty)
        if let copied = TagClipboard.decode(copiedTagsJSON) {
            let s = TagSuggester.summary(copied)
            Button { pasteTags(photo) } label: {
                Label(s.isEmpty ? "Paste tags" : "Paste tags · \(s)", systemImage: "doc.on.clipboard")
            }
        }
        Divider()
        Button { shareOne(photo) } label: { Label("Share", systemImage: "square.and.arrow.up") }
        Divider()
        Button(role: .destructive) { photoToDelete = photo } label: { Label("Delete", systemImage: "trash") }
    }

    private func copyTags(_ photo: Photo) {
        copiedTagsJSON = TagClipboard.encode(photo.humanTags)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    private func pasteTags(_ photo: Photo) {
        guard let tags = TagClipboard.decode(copiedTagsJSON) else { return }
        photo.humanTags = photo.humanTags.mergingTaxonomy(from: tags)
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func tile(_ photo: Photo, selected sel: Bool) -> some View {
        PhotoThumbnail(photo: photo)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay { if photo.isFavorite {
                Rectangle().strokeBorder(Color.red, lineWidth: 2)
            } }
            .overlay(alignment: .topLeading) { TileBadges(photo: photo).padding(4) }
            .overlay { if selecting {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(sel ? 0.35 : 0)
                    Image(systemName: sel ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(sel ? Palette.coral : .white)
                        .font(.system(size: 20)).padding(5)
                        .shadow(radius: 1)
                }
            } }
    }

    private func toggleFavorite(_ photo: Photo) {
        photo.isFavorite.toggle()
        try? modelContext.save()
    }

    private func shareOne(_ photo: Photo) {
        // Via PhotoImage.full so references (camera shots) and edits are included
        // — `imageData` is empty for references, so the old path shared nothing.
        Task {
            if let img = await PhotoImage.full(for: photo) { shareItems = [img]; showShare = true }
        }
    }

    private func toggleSelect(_ p: Photo) {
        if selected.contains(p.id) { selected.remove(p.id) } else { selected.insert(p.id) }
    }

    // MARK: Result bar / pills

    private var resultBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if filterFavorites { filterPill(label: "♥ Favourites") { filterFavorites = false } }
                    if filterMinRating > 0 { filterPill(label: "★ \(filterMinRating)+") { filterMinRating = 0 } }
                    if let ft = filterType { filterPill(label: ft.capitalized) { filterType = nil } }
                    if let ty = filterTypology { filterPill(label: ty) { filterTypology = nil } }
                    if let mt = filterMaterial { filterPill(label: mt) { filterMaterial = nil } }
                    if filterYear > 0 { filterPill(label: String(filterYear)) { filterYear = 0 } }
                    if let fp = filterProject { filterPill(label: fp) { filterProject = nil } }
                }
            }
            Text("\(filtered.count) of \(photos.count)")
                .font(.caption).foregroundStyle(Palette.ink3)
                .fixedSize()
        }
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func filterPill(label: String, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.medium))
            Button(action: clear) { Image(systemName: "xmark.circle.fill") }.foregroundStyle(Palette.ink3)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Palette.tile))
        .foregroundStyle(Palette.ink)
    }

    // MARK: Selection action bar

    private var selectionBar: some View {
        HStack {
            Button { shareSelected() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                .disabled(selected.isEmpty)
            Spacer()
            Button { composeBoard() } label: { Label("Board", systemImage: "doc.richtext") }
                .disabled(selected.isEmpty)
            Spacer()
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.bar)
    }

    /// Open the board composer pre-loaded with the current selection (in gallery
    /// order). The composer handles reorder / size / title / save / export.
    private func composeBoard() {
        composerPhotos = filtered.filter { selected.contains($0.id) }
        guard !composerPhotos.isEmpty else { return }
        showComposer = true
    }

    private func deleteSelected() {
        for p in photos where selected.contains(p.id) { modelContext.delete(p) }
        try? modelContext.save()
        selected.removeAll(); selecting = false
    }

    private func shareSelected() {
        // Load via PhotoImage.full (references + edits), sequentially so only a
        // couple of bitmaps live at once, and cap the batch so Select-All over a
        // huge library can't decode thousands of full-size images into memory.
        let targets = Array(photos.filter { selected.contains($0.id) }.prefix(40))
        guard !targets.isEmpty else { return }
        Task {
            var imgs: [UIImage] = []
            for p in targets {
                if let img = await PhotoImage.full(for: p) { imgs.append(img) }
            }
            guard !imgs.isEmpty else { return }
            shareItems = imgs; showShare = true
        }
    }

    // MARK: Chrome

    private var lensPicker: some View {
        // App-unified pill toggle (same lemon language as tagging), not a native
        // segmented control. Stays enabled during Select so you can move between
        // lenses while picking.
        PillToggle(selection: $lens,
                   options: GalleryLens.allCases.map { PillOption(value: $0, label: $0.rawValue) })
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera.aperture").font(.system(size: 56, weight: .thin)).foregroundStyle(Palette.ink3)
            (Text("Archi").foregroundStyle(Palette.ink) + Text(".vé").foregroundStyle(Palette.coral))
                .font(.system(size: 34, weight: .bold, design: .serif))
            Text("No photos yet").foregroundStyle(Palette.ink3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tile badges

/// Untagged red dot (top-left), project lemon pill, reference mint pill.
struct TileBadges: View {
    let photo: Photo
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if photo.isUntagged {
                Circle().fill(Palette.coral).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
            }
            if let proj = photo.project, !proj.isEmpty {
                pill(proj, Palette.lemon)
            } else if let ref = referenceLabel {
                pill(ref, Palette.mint)
            }
        }
    }
    private var referenceLabel: String? {
        let t = photo.humanTags
        switch t.type {
        case "building": return t.typology
        case "element": return t.element
        case "graphic": return t.graphicKind?.capitalized
        default: return nil
        }
    }
    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(color))
            .foregroundStyle(.black)
    }
}

// MARK: - Filter sheet

private struct FilterSheet: View {
    @Binding var type: String?
    @Binding var typology: String?
    @Binding var material: String?
    @Binding var year: Int
    @Binding var project: String?
    @Binding var favorites: Bool
    @Binding var minRating: Int
    let projects: [String]
    let typologies: [String]
    let materials: [String]
    let years: [Int]
    @Environment(\.dismiss) private var dismiss

    private let types: [(String, String)] = [("untagged", "Untagged"), ("building", "Building"),
                                              ("element", "Element"), ("graphic", "Graphic")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $favorites) {
                        Label("Favourites only", systemImage: "heart.fill")
                    }
                    .tint(Palette.coral)
                    Picker("Minimum rating", selection: $minRating) {
                        Text("Any").tag(0)
                        ForEach(1...5, id: \.self) { n in
                            Text(String(repeating: "★", count: n)).tag(n)
                        }
                    }
                }
                Section("Type") {
                    Picker("Type", selection: Binding(get: { type ?? "all" },
                                                      set: { type = $0 == "all" ? nil : $0 })) {
                        Text("All").tag("all")
                        ForEach(types, id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.inline).labelsHidden()
                }
                if !typologies.isEmpty || !materials.isEmpty || !years.isEmpty {
                    Section("Details") {
                        if !typologies.isEmpty {
                            Picker("Typology", selection: Binding(get: { typology ?? "" },
                                                                  set: { typology = $0.isEmpty ? nil : $0 })) {
                                Text("Any").tag("")
                                ForEach(typologies, id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu)
                        }
                        if !materials.isEmpty {
                            Picker("Material", selection: Binding(get: { material ?? "" },
                                                                  set: { material = $0.isEmpty ? nil : $0 })) {
                                Text("Any").tag("")
                                ForEach(materials, id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu)
                        }
                        if !years.isEmpty {
                            Picker("Year", selection: $year) {
                                Text("Any").tag(0)
                                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                            }.pickerStyle(.menu)
                        }
                    }
                }
                if !projects.isEmpty {
                    Section("Project") {
                        Picker("Project", selection: Binding(get: { project ?? "" },
                                                             set: { project = $0.isEmpty ? nil : $0 })) {
                            Text("Any").tag("")
                            ForEach(projects, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        type = nil; typology = nil; material = nil; year = 0
                        project = nil; favorites = false; minRating = 0
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(Palette.coral)
    }
}

// MARK: - Share sheet

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Drag-to-paint selection (UIKit pan that coexists with scrolling)

/// A UIKit pan recognizer bridged into SwiftUI. Its delegate allows simultaneous
/// recognition with the scroll view's own pan, so a horizontal paint-drag and a
/// vertical scroll can both work — something a plain SwiftUI DragGesture can't do
/// inside a ScrollView (it steals the touch and kills scrolling).
@available(iOS 18.0, *)
struct PaintPanGesture: UIGestureRecognizerRepresentable {
    var onChange: (CGPoint, CGSize) -> Void
    var onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        g.cancelsTouchesInView = false
        return g
    }
    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        switch g.state {
        case .began, .changed:
            // Location in the grid's scrolling coordinate space, so the row index is
            // correct regardless of how far the grid has been scrolled.
            let loc = context.converter.location(in: .named("galgrid"))
            let t = g.translation(in: g.view)
            onChange(loc, CGSize(width: t.x, height: t.y))
        case .ended, .cancelled, .failed:
            onEnd()
        default: break
        }
    }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

extension View {
    /// Attach the paint-select pan when `active` (iOS 18+); otherwise unchanged.
    @ViewBuilder
    func paintSelectable(active: Bool,
                         onChange: @escaping (CGPoint, CGSize) -> Void,
                         onEnd: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *), active {
            self.gesture(PaintPanGesture(onChange: onChange, onEnd: onEnd))
        } else {
            self
        }
    }
}

// MARK: - Thumbnail

/// Thumbnail that decodes a downsampled image off the main thread.
struct PhotoThumbnail: View {
    let photo: Photo
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.tile
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottomTrailing) {
                if photo.isVideo {
                    let d = max(9, min(geo.size.width, geo.size.height) * 0.2)
                    Image(systemName: "play.fill")
                        .font(.system(size: d * 0.62, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: d, height: d)
                        .background(.black.opacity(0.4), in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 1)
                        .padding(d * 0.34)
                        .allowsHitTesting(false)
                }
            }
            .task(id: photo.id) {
                if image != nil { return }
                let base: UIImage?
                // Videos carry their (framing-cropped) poster in imageData.
                if photo.isVideo, !photo.imageData.isEmpty {
                    base = await Self.thumbnail(from: photo.imageData, maxPixel: 400)
                } else if let id = photo.assetLocalID, !id.isEmpty {
                    base = await PhotosLibrary.image(localID: id, maxPixel: 400)
                } else {
                    base = await Self.thumbnail(from: photo.imageData, maxPixel: 400)
                }
                if let base { image = (photo.hasEdits && !photo.isVideo) ? PhotoEdits.render(base, photo) : base }
            }
        }
    }

    static func thumbnail(from data: Data, maxPixel: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
    }
}

// MARK: - Map lens

private struct MapLens: View {
    let photos: [Photo]
    var selecting: Bool

    var body: some View {
        if photos.isEmpty {
            ContentUnavailableView("No located photos", systemImage: "mappin.slash",
                                   description: Text("Photos you take with location on will appear here."))
        } else {
            Map {
                ForEach(photos) { photo in
                    if let lat = photo.latitude, let lon = photo.longitude {
                        Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                            NavigationLink(value: photo) {
                                PhotoThumbnail(photo: photo)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2))
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
