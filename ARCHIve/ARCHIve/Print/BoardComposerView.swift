import SwiftUI
import SwiftData

/// Compose a board from a selection (or edit a saved one): set a title, pick a
/// layout, reorder by dragging, remove photos, then Save and/or Export a PDF.
struct BoardComposerView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var allPhotos: [Photo]

    private let existing: Board?
    @State private var title: String
    @State private var layout: BoardLayout
    @State private var order: [String]          // ordered photo ids
    @State private var working = false
    @State private var shareURL: URL?
    @State private var showShare = false

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
    private var orderedPhotos: [Photo] { order.compactMap { byID[$0] } }

    var body: some View {
        NavigationStack {
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
                Section(order.isEmpty ? "No photos" : "\(order.count) photos · drag to reorder") {
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
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { order.remove(atOffsets: $0) }
                }
            }
            .environment(\.editMode, .constant(.active))   // always-on drag handles + delete
            .navigationTitle(existing == nil ? "New board" : "Edit board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { save() } label: { Label(existing == nil ? "Save board" : "Save changes", systemImage: "tray.and.arrow.down") }
                            .disabled(order.isEmpty)
                        Button { Task { await export() } } label: { Label("Export PDF", systemImage: "square.and.arrow.up") }
                            .disabled(order.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .overlay {
                if working {
                    VStack(spacing: 12) { ProgressView(); Text("Composing…").font(.subheadline) }
                        .padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .sheet(isPresented: $showShare) { if let shareURL { ActivityView(items: [shareURL]) } }
        }
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

    private func export() async {
        working = true
        let url = await BoardRenderer.makePDF(photos: orderedPhotos, layout: layout, title: title)
        working = false
        if let url { shareURL = url; showShare = true }
    }
}

/// The shelf of saved boards — tap to reopen in the composer.
struct BoardsListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Board.updatedAt, order: .reverse) private var boards: [Board]
    @State private var editing: Board?

    var body: some View {
        NavigationStack {
            Group {
                if boards.isEmpty {
                    ContentUnavailableView("No boards yet", systemImage: "doc.richtext",
                        description: Text("Select photos in the gallery and tap Board to compose one."))
                } else {
                    List {
                        ForEach(boards) { b in
                            Button { editing = b } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: b.layout.icon)
                                        .font(.system(size: 18)).foregroundStyle(Palette.coral)
                                        .frame(width: 38, height: 38)
                                        .background(RoundedRectangle(cornerRadius: 9).fill(Palette.tile))
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
            .sheet(item: $editing) { BoardComposerView(board: $0) }
        }
    }
}
