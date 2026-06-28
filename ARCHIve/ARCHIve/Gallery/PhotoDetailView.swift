import SwiftUI
import SwiftData
import UIKit

/// Swipeable detail: pages horizontally through the archive (newest first),
/// starting at the tapped photo. Each page shows the image (tap to pinch-zoom
/// fullscreen) and its tags as an **editable form** that auto-saves — so you can
/// retag straight away without a separate edit screen.
struct PhotoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Photo.createdAt, order: .reverse) private var photos: [Photo]

    @State private var selection: String
    @State private var introspecting = false
    @State private var confirmDelete = false
    @State private var showShare = false
    @State private var editing = false
    @State private var refresh = 0          // bump to reload images after an edit
    @State private var currentImage: UIImage?
    /// A copied set of human tags, ready to paste onto another photo. Stored as
    /// JSON so it survives paging between photos and app relaunches.
    @AppStorage(TagClipboard.key) private var copiedTagsJSON = ""

    init(photoID: String) { _selection = State(initialValue: photoID) }

    private var current: Photo? { photos.first { $0.id == selection } }

    /// The tags currently on the clipboard, if any decode.
    private var copiedTags: HumanTags? { TagClipboard.decode(copiedTagsJSON) }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(photos) { photo in
                PhotoPage(photo: photo, refresh: refresh) { img in currentImage = img; introspecting = true }
                    .tag(photo.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .task(id: "\(selection)#\(refresh)") {
            currentImage = nil
            // Re-check identity after the await: a slow load for a photo the user
            // has already paged away from must not poison currentImage (which Share
            // and zoom read directly).
            let target = selection
            if let c = photos.first(where: { $0.id == target }) {
                let img = await PhotoImage.full(for: c)
                if selection == target { currentImage = img }
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(current.map { $0.createdAt.formatted(date: .abbreviated, time: .shortened) } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = true } label: { Label("Edit photo", systemImage: "slider.horizontal.3") }
                        .disabled(current == nil)
                    if let current {
                        Button { current.isFavorite.toggle(); try? modelContext.save() } label: {
                            Label(current.isFavorite ? "Remove Favourite" : "Favourite",
                                  systemImage: current.isFavorite ? "heart.slash" : "heart")
                        }
                    }
                    Divider()
                    Button { copyTags() } label: { Label("Copy tags", systemImage: "doc.on.doc") }
                        .disabled(current?.humanTags.isEmpty ?? true)
                    if let copied = copiedTags {
                        let s = TagSuggester.summary(copied)
                        Button { pasteTags() } label: {
                            Label(s.isEmpty ? "Paste tags" : "Paste tags · \(s)", systemImage: "doc.on.clipboard")
                        }
                        .disabled(current == nil)
                    }
                    Divider()
                    Button { showShare = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(current == nil)
            }
        }
        .fullScreenCover(isPresented: $introspecting) {
            IntrospectionView(image: currentImage) { introspecting = false }
        }
        .fullScreenCover(isPresented: $editing) {
            if let current {
                PhotoEditorView(photo: current) { editing = false; refresh += 1 }
            }
        }
        .sheet(isPresented: $showShare) {
            if let img = currentImage { ActivityView(items: [img]) }
        }
        .alert("Delete this photo?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { deleteCurrent() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes the photo from your archive.")
        }
    }

    /// Copy the current photo's human tags to the clipboard (machine tags and the
    /// project are intentionally left out — those stay per-photo).
    private func copyTags() {
        guard let current else { return }
        copiedTagsJSON = TagClipboard.encode(current.humanTags)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Apply the clipboard tags to the current photo (replaces its human tags).
    private func pasteTags() {
        guard let current, let tags = copiedTags else { return }
        current.humanTags = current.humanTags.mergingTaxonomy(from: tags)
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Delete the current page, then move to a neighbour or leave if it was the
    /// last one.
    private func deleteCurrent() {
        guard let current, let idx = photos.firstIndex(where: { $0.id == current.id }) else { return }
        let neighbour = photos[safe: idx + 1] ?? photos[safe: idx - 1]
        modelContext.delete(current)
        try? modelContext.save()
        if let neighbour { selection = neighbour.id } else { dismiss() }
    }
}

/// A single detail page: tappable image + its tags as an inline, auto-saving
/// editor.
private struct PhotoPage: View {
    @Bindable var photo: Photo
    var refresh: Int
    var onZoom: (UIImage) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var image: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let image {
                    Button { onZoom(image) } label: {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                } else {
                    Rectangle().fill(Palette.tile)
                        .aspectRatio(4/3, contentMode: .fit)
                        .overlay(ProgressView())
                }

                // Editable tags, right here — changes save automatically.
                TagForm(
                    tags: Binding(get: { photo.humanTags },
                                  set: { photo.humanTags = $0; try? modelContext.save() }),
                    project: Binding(get: { photo.project ?? "" },
                                     set: { photo.project = $0.isEmpty ? nil : $0; try? modelContext.save() }),
                    labelImage: Binding(get: { photo.labelImageData.flatMap { UIImage(data: $0) } },
                                        set: { photo.labelImageData = $0?.jpegData(compressionQuality: 0.85); try? modelContext.save() }),
                    isLibraryPhoto: photo.isReference && !photo.isCameraShot
                )
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 28)
        }
        .task(id: "\(photo.id)#\(refresh)") {
            image = await PhotoImage.full(for: photo)
        }
    }
}

private extension Array {
    /// Safe index lookup — returns nil instead of trapping out of bounds.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
