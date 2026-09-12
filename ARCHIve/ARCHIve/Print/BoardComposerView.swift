import SwiftUI
import SwiftData
import PDFKit

/// Compose a board from a selection (or edit a saved one): set a title, pick a
/// layout, reorder by dragging, remove photos, then Save and/or Export a PDF.
struct BoardComposerView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Query private var allPhotos: [Photo]

    private let existing: Board?
    @State private var title: String
    @State private var layout: BoardLayout
    @State private var order: [String]          // ordered photo ids
    @State private var working = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var previewURL: URL?
    @State private var showPreview = false
    @State private var showAddPhotos = false
    @State private var confirmDelete = false
    @Environment(\.horizontalSizeClass) private var hSize
    // iPad live preview (right pane)
    @State private var livePDF: URL?
    @State private var renderingPreview = false
    @State private var previewVersion = 0   // bumps each render so the PDF view reloads the same-named temp file

    /// New board from a gallery selection.
    init(photos: [Photo]) {
        existing = nil
        _title = State(initialValue: "")
        _layout = State(initialValue: .posterB1)
        _order = State(initialValue: photos.map(\.id))
    }
    /// Edit an existing saved board.
    init(board: Board) {
        existing = board
        _title = State(initialValue: board.title)
        _layout = State(initialValue: board.layout)
        _order = State(initialValue: board.photoIDs)
    }

    private var byID: [String: Photo] { Dictionary(allPhotos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var orderedPhotos: [Photo] {
        let map = byID                       // build once, not once per id
        return order.compactMap { map[$0] }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
            List {
                Section {
                    TextField("Board title", text: $title)
                        .autocorrectionDisabled()
                    Picker("Layout", selection: $layout) {
                        ForEach(BoardLayout.allCases) { l in
                            Label(l.label, systemImage: l.icon).tag(l)
                        }
                    }
                    Text(layout.blurb).font(.caption).foregroundStyle(.secondary)
                }
                // iPhone: show the board itself, live — so "what will this look
                // like?" is answered without tapping. iPad shows it in pane two.
                if hSize != .regular {
                    Section { previewCard.listRowInsets(EdgeInsets()) }
                }
                Section {
                    Button { showAddPhotos = true } label: {
                        Label("Add photos", systemImage: "plus.circle.fill")
                            .foregroundStyle(Palette.coral)
                    }
                }
                Section(orderedPhotos.isEmpty ? "No photos" : "\(orderedPhotos.count) photos · drag to reorder") {
                    ForEach(orderedPhotos) { photo in
                        HStack(spacing: 12) {
                            PhotoThumbnail(photo: photo)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plateTitle(photo)).font(.subheadline).lineLimit(1)
                                let sub = [photo.humanTags.place, monthString(photo.createdAt)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    // The list shows only RESOLVED photos, so move/delete offsets are
                    // into that sublist — apply them there and keep any unresolved ids
                    // (deleted-from-archive or not-yet-synced) so Save can't drop them.
                    .onMove { from, to in
                        var resolved = order.filter { byID[$0] != nil }
                        let unresolved = order.filter { byID[$0] == nil }
                        resolved.move(fromOffsets: from, toOffset: to)
                        order = resolved + unresolved
                    }
                    .onDelete { offsets in
                        var resolved = order.filter { byID[$0] != nil }
                        let unresolved = order.filter { byID[$0] == nil }
                        resolved.remove(atOffsets: offsets)
                        order = resolved + unresolved
                    }
                }
            }
            .frame(maxWidth: hSize == .regular ? 380 : .infinity)
            // iPad: a live board preview sits beside the editing list, updating a
            // beat after you reorder, retitle or switch layout.
            if hSize == .regular {
                Divider()
                livePreviewPane
            }
            }
            .environment(\.editMode, .constant(.active))   // always-on drag handles + delete
            // Drive the live render for BOTH sizes — the iPhone card and the iPad
            // pane each just display `livePDF`.
            .task(id: previewToken) { await renderPreview() }
            .navigationTitle(existing == nil ? "New board" : "Edit board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                // The board is on screen now, so there's no Preview button. Export
                // gets its own share icon instead of hiding in a menu, and ⋯ keeps
                // only the destructive action (saved boards only).
                if existing != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label("Delete board", systemImage: "trash")
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // The layout already fixes the size, so there's nothing to
                        // pick — only which file you want. Lead with the one that
                        // suits the sheet you composed.
                        let image = Button { Task { await exportImage(pixels: layout.exportPixels) } } label: {
                            Label("Export image", systemImage: "photo")
                        }
                        let pdf = Button { Task { await export() } } label: {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }
                        if layout.isSocial { image; pdf } else { pdf; image }
                    } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(order.isEmpty || working)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(existing == nil ? "Save" : "Done") { save() }
                        .fontWeight(.semibold).disabled(order.isEmpty)
                }
            }
            .overlay {
                if working {
                    VStack(spacing: 12) { ProgressView(); Text("Composing…").font(.subheadline) }
                        .padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .sheet(isPresented: $showShare, onDismiss: {
                // Exporting a board is a genuine success moment — ask for a review
                // once the share sheet closes (gated to once per version).
                ReviewPrompt.ask(requestReview)
            }) { if let shareURL { ActivityView(items: [shareURL]) } }
            .sheet(isPresented: $showPreview) { if let previewURL { BoardPreviewSheet(url: previewURL) } }
            .sheet(isPresented: $showAddPhotos) {
                BoardPhotoPicker(excluding: Set(order)) { ids in
                    for id in ids where !order.contains(id) { order.append(id) }
                }
            }
            .confirmationDialog("Delete this board?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete board", role: .destructive) { deleteBoard() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes the board only — your photos stay in the archive.") }
        }
    }

    /// The sheet is portrait for posters, landscape for the journal — give each
    /// enough height that the fitted page stays legible.
    private var previewCardHeight: CGFloat {
        switch layout {
        case .journalA4: return 250                      // landscape spread
        case .socialStory: return 360                    // 9:16 is tall and narrow
        case .socialSquare, .socialPortrait: return 300
        default: return 330                              // print posters
        }
    }

    /// iPhone: the live board, inline in the form. Tapping opens the same
    /// full-screen preview the old Preview button did — so the button isn't
    /// needed, because the answer it gave is already on screen.
    private var previewCard: some View {
        Button { Task { await preview() } } label: {
            ZStack {
                Palette.tile
                if let livePDF {
                    // .id(previewVersion) forces a reload each render — makePDF
                    // reuses one temp filename, so the URL never signals a change.
                    PDFKitView(url: livePDF, fitPage: true).id(previewVersion)
                        .allowsHitTesting(false)      // let the button take the tap
                } else if order.isEmpty {
                    Text("Add photos to preview").font(.callout).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
                if renderingPreview {
                    ProgressView().padding(8)
                        .background(.regularMaterial, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(10)
                }
            }
            .frame(height: previewCardHeight)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .padding(7)
                    .background(.regularMaterial, in: Circle())
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .disabled(order.isEmpty || working)
    }

    /// The right-hand live preview (iPad): the rendered board PDF, re-rendered a
    /// beat after the order, layout or title changes. Reuses makePDF, so it's the
    /// exact thing Export produces and handles both poster and journal layouts.
    private var livePreviewPane: some View {
        ZStack {
            Palette.tile
            if let livePDF {
                // .id(previewVersion) forces a reload each render — makePDF reuses
                // the same temp filename, so the URL alone never signals a change.
                PDFKitView(url: livePDF).id(previewVersion).ignoresSafeArea(edges: .bottom)
            } else if order.isEmpty {
                Text("Add photos to preview").font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            if renderingPreview {
                ProgressView().padding(10)
                    .background(.regularMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)
            }
        }
    }

    /// One value that changes whenever anything affecting the render changes, so a
    /// single `.task(id:)` cancels the in-flight render and starts a fresh one.
    private var previewToken: String { "\(layout.rawValue)|\(title)|\(order.joined(separator: ","))" }

    private func renderPreview() async {
        guard !order.isEmpty else { livePDF = nil; return }
        renderingPreview = true
        defer { renderingPreview = false }
        // Debounce: let rapid reorders / typing settle before the heavier render.
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        let url = await BoardRenderer.makePDF(photos: orderedPhotos, layout: layout, title: title)
        if Task.isCancelled { return }
        livePDF = url
        previewVersion &+= 1
    }

    private func plateTitle(_ p: Photo) -> String {
        let t = p.humanTags
        return [t.typology, t.element, t.graphicKind?.capitalized, t.type?.capitalized]
            .compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Untagged"
    }
    private func monthString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy.MM"; return f.string(from: d)
    }

    private func save() {
        if let b = existing {
            b.title = title; b.layout = layout; b.photoIDs = order; b.updatedAt = Date()
        } else {
            ctx.insert(Board(title: title, layout: layout, photoIDs: order))
        }
        try? ctx.save()
        dismiss()
    }

    /// Delete the board record. Photos are untouched — a board only stores a list
    /// of photo ids, never the images themselves.
    private func deleteBoard() {
        if let b = existing { ctx.delete(b); try? ctx.save() }
        dismiss()
    }

    private func export() async {
        guard !working else { return }   // no overlapping exports (shared Geocoder, memory)
        working = true
        let url = await BoardRenderer.makePDF(photos: orderedPhotos, layout: layout, title: title)
        working = false
        if let url { shareURL = url; showShare = true }
    }

    /// Export the board as a social-sized image (with the attribution mark per the
    /// Settings toggle) and hand it to the share sheet.
    /// Every layout defines its own pixel size, so the image exports directly
    /// rather than asking which size to use.
    private func exportImage(pixels: CGSize) async {
        guard !working else { return }
        working = true
        let url = await BoardRenderer.makeImage(photos: orderedPhotos, pixels: pixels, title: title)
        working = false
        if let url { shareURL = url; showShare = true }
    }

    /// Render the board and show it full-screen — the same PDF that Export
    /// produces, so it's an exact preview.
    private func preview() async {
        guard !working else { return }
        working = true
        let url = await BoardRenderer.makePDF(photos: orderedPhotos, layout: layout, title: title)
        working = false
        if let url { previewURL = url; showPreview = true }
    }
}

/// Full-screen preview of a rendered board PDF, with a Share button.
private struct BoardPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                    }
                }
                .sheet(isPresented: $showShare) { ActivityView(items: [url]) }
        }
    }
}

/// A zoomable PDF view (PDFKit) for previewing a rendered board.
private struct PDFKitView: UIViewRepresentable {
    let url: URL
    /// Fit one whole page in the view (for the small inline card). The default
    /// scrolling mode is kept for the full-screen preview, so a multi-page
    /// journal can still be paged through there.
    var fitPage = false
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.backgroundColor = .systemGray6
        if fitPage {
            v.displayMode = .singlePage
            v.displaysPageBreaks = false
        }
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

/// The shelf of saved boards — tap to reopen, or "+" to start a new one.
struct BoardsListView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.updatedAt, order: .reverse) private var boards: [Board]
    @Query private var allPhotos: [Photo]
    @State private var route: Route?

    private var byID: [String: Photo] { Dictionary(allPhotos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private func cover(_ b: Board) -> [Photo] { b.photoIDs.prefix(8).compactMap { byID[$0] } }

    /// One composer sheet, opened either fresh ("New board") or on a saved board.
    private enum Route: Identifiable {
        case new
        case edit(Board)
        var id: String { switch self { case .new: "new"; case .edit(let b): b.id } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if boards.isEmpty {
                    ContentUnavailableView {
                        Label("No boards yet", systemImage: "doc.richtext")
                    } description: {
                        Text("Create a board here, or select photos in the gallery and tap Board.")
                    } actions: {
                        Button { route = .new } label: { Label("New board", systemImage: "plus") }
                            .buttonStyle(.borderedProminent).tint(Palette.coral)
                    }
                } else {
                    List {
                        ForEach(boards) { b in
                            Button { route = .edit(b) } label: {
                                HStack(spacing: 12) {
                                    BoardMiniature(photos: cover(b)).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.title.isEmpty ? "Untitled board" : b.title)
                                            .font(.headline).foregroundStyle(Palette.ink)
                                        Text("\(b.layout.label) · \(b.photoIDs.count) photos")
                                            .font(.caption).foregroundStyle(Palette.ink3)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.ink3)
                                }
                            }
                        }
                        .onDelete { idx in idx.map { boards[$0] }.forEach(ctx.delete); try? ctx.save() }
                    }
                }
            }
            .navigationTitle("Boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Clear way back to the gallery (this is a sheet over it).
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Gallery", systemImage: "chevron.left") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { route = .new } label: { Label("New board", systemImage: "plus") }
                }
            }
            .sheet(item: $route) { r in
                switch r {
                case .new: BoardComposerView(photos: [])
                case .edit(let b): BoardComposerView(board: b)
                }
            }
        }
    }
}

/// A little thumbnail of a board for the shelf: one photo fills it, several tile
/// into a small grid — so a board reads at a glance instead of a generic icon.
private struct BoardMiniature: View {
    let photos: [Photo]

    var body: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(Palette.tile)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.hairline, lineWidth: 1))
    }

    @ViewBuilder private var content: some View {
        if photos.isEmpty {
            Image(systemName: "doc.richtext").font(.system(size: 16)).foregroundStyle(Palette.ink3)
        } else if photos.count == 1 {
            PhotoThumbnail(photo: photos[0])
        } else {
            // 2×2 grid; with 2–3 photos the cells cycle so none sit empty.
            let g = Array(photos.prefix(4))
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow { cell(g, 0); cell(g, 1) }
                GridRow { cell(g, 2); cell(g, 3) }
            }
        }
    }

    private func cell(_ g: [Photo], _ i: Int) -> some View {
        PhotoThumbnail(photo: g[i % g.count]).clipped()
    }
}

/// Pick photos from the archive to add to a board. Shows everything not already
/// on the board; search narrows by tag/typology/material (e.g. "civic", "brick")
/// or a 4-digit year against the capture date (e.g. "2025"). "Select all" grabs
/// every photo currently matching — so a whole scoped board is two taps.
private struct BoardPhotoPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Photo.createdAt, order: .reverse) private var allPhotos: [Photo]
    let excluding: Set<String>
    var onAdd: ([String]) -> Void
    @State private var picked: [String] = []
    @State private var search = ""

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    /// Not-already-on-the-board photos that match the search. Each word must hit
    /// the photo's tag text OR (if it's 4 digits) the year it was taken.
    private var candidates: [Photo] {
        let base = allPhotos.filter { !excluding.contains($0.id) }
        let words = search.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return base }
        let cal = Calendar.current
        return base.filter { p in
            let txt = p.searchText
            let year = String(cal.component(.year, from: p.createdAt))
            return words.allSatisfy { w in txt.contains(w) || (w.count == 4 && year == w) }
        }
    }

    private var allPicked: Bool { !candidates.isEmpty && candidates.allSatisfy { picked.contains($0.id) } }
    private func toggleAll() {
        if allPicked {
            let vis = Set(candidates.map(\.id)); picked.removeAll { vis.contains($0) }
        } else {
            for p in candidates where !picked.contains(p.id) { picked.append(p.id) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No more photos" : "No matches",
                        systemImage: "photo.on.rectangle",
                        description: Text(search.isEmpty
                            ? "Every photo in your archive is already on this board."
                            : "No photos match “\(search)”. Try a tag, material, or a year."))
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("\(candidates.count) photo\(candidates.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(Palette.ink3)
                            Spacer()
                            Button(allPicked ? "Clear" : "Select all") { toggleAll() }
                                .font(.caption.weight(.semibold)).foregroundStyle(Palette.coral)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        ScrollView {
                            LazyVGrid(columns: cols, spacing: 2) {
                                ForEach(candidates) { p in
                                    let sel = picked.contains(p.id)
                                    Button {
                                        if sel { picked.removeAll { $0 == p.id } } else { picked.append(p.id) }
                                    } label: {
                                        Color.clear
                                            .aspectRatio(1, contentMode: .fit)
                                            .overlay { PhotoThumbnail(photo: p) }
                                            .clipped()
                                            .contentShape(Rectangle())
                                            .overlay(alignment: .topTrailing) {
                                                if sel {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.white, Palette.coral)
                                                        .padding(4).shadow(radius: 1)
                                                }
                                            }
                                            .overlay {
                                                if sel { Rectangle().strokeBorder(Palette.coral, lineWidth: 2) }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(2)
                        }
                    }
                }
            }
            .navigationTitle(picked.isEmpty ? "Add photos" : "\(picked.count) selected")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Tag, material, or year")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(picked); dismiss() }
                        .fontWeight(.semibold).disabled(picked.isEmpty)
                }
            }
            .background(Palette.paper.ignoresSafeArea())
        }
    }
}
