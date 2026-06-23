import SwiftUI
import SwiftData

/// Post-capture tagging. Binds to a freshly-saved Photo so the image is never
/// lost — Save commits the chosen tags, Skip leaves it untagged (only `type`
/// kept). The editable form itself lives in `TagForm`.
struct TagSheetView: View {
    @Bindable var photo: Photo
    /// When set, Save applies the chosen tags to *every* photo here (batch
    /// tagging from the library); `photo` is just the one shown in the card.
    var batchPhotos: [Photo]? = nil
    /// Sequential ("one by one") tagging: the previous photo's tags/project for
    /// one-tap reuse, the N-of-M progress, and an exit hook.
    var previousTags: HumanTags? = nil
    var previousProject: String? = nil
    var progress: (current: Int, total: Int)? = nil
    var onExit: (() -> Void)? = nil
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var tags = HumanTags()
    @State private var project = ""
    @State private var showFullscreen = false
    @State private var headerImage: UIImage?
    @State private var labelImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            if let progress { sequentialBar(progress) }
            header
            Divider().overlay(Palette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let prev = previousTags, prev.type != nil { usePreviousButton(prev) }
                    TagForm(tags: $tags, project: $project, labelImage: $labelImage,
                            isLibraryPhoto: photo.isReference && !photo.isCameraShot)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .onAppear {
            tags = photo.humanTags; project = photo.project ?? ""
            if let d = photo.labelImageData { labelImage = UIImage(data: d) }
        }
        .task(id: photo.id) { headerImage = await PhotoImage.full(for: photo) }
        .interactiveDismissDisabled(false)
        .fullScreenCover(isPresented: $showFullscreen) {
            IntrospectionView(image: headerImage) { showFullscreen = false }
        }
    }

    /// "One by one" session header: progress + an exit out of the whole run.
    private func sequentialBar(_ p: (current: Int, total: Int)) -> some View {
        HStack {
            Text("\(p.current) of \(p.total)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink3)
            Spacer()
            Button("Done") { onExit?() }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.coral)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)
    }

    /// One-tap reuse of the previous photo's tags — fast path for a "cleaning" run.
    private func usePreviousButton(_ prev: HumanTags) -> some View {
        Button {
            tags = prev
            if let pp = previousProject { project = pp }
        } label: {
            Label("Use previous tags", systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.coral.opacity(0.14)))
                .foregroundStyle(Palette.coral)
        }
        .buttonStyle(.plain)
    }

    // MARK: Header — Skip · photo · Save

    /// A big full-width 1:1 photo with Skip / Save floating on its lower corners.
    private var header: some View {
        photoCard
            .overlay(alignment: .bottomLeading) {
                skipButton.padding(.leading, 24).padding(.bottom, 18)
            }
            .overlay(alignment: .bottomTrailing) {
                saveButton.padding(.trailing, 24).padding(.bottom, 18)
            }
    }

    /// Skip — a frosted-glass pill that picks up the photo behind it.
    private var skipButton: some View {
        Button { finish() } label: {
            HStack(spacing: 7) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                Text("Skip").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// Save — the primary action: a light-glass pill with dark text (neutral, no
    /// accent colour while tagging). Frosted + dimmed until a Kind is chosen.
    private var saveButton: some View {
        let enabled = tags.type != nil
        return Button { commit() } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                Text("Save").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(enabled ? Color(white: 0.12) : .white)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background {
                if enabled { Capsule().fill(Color.white.opacity(0.92)) }
                else { Capsule().fill(.ultraThinMaterial) }
            }
            .overlay(Capsule().strokeBorder(.white.opacity(enabled ? 0 : 0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(enabled ? 0.28 : 0.2), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.75)
    }

    /// Tap the photo (anywhere but the buttons) to inspect it fullscreen.
    private var photoCard: some View {
        Button { showFullscreen = true } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack {
                        if let img = headerImage {
                            Image(uiImage: img).resizable().scaledToFill()
                        } else {
                            Palette.tile
                        }
                        LinearGradient(colors: [.clear, .black.opacity(0.45)],
                                       startPoint: .center, endPoint: .bottom)
                    }
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Circle().fill(.black.opacity(0.4)))
                        .padding(10)
                }
                .overlay(alignment: .topLeading) {
                    if let n = batchPhotos?.count, n > 1 {
                        Text("Tagging \(n) photos")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(Palette.coral))
                            .padding(10)
                    }
                }
        }
        .buttonStyle(.plain)
    }


    // MARK: Persist

    private func commit() {
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let proj = trimmed.isEmpty ? nil : trimmed
        for p in (batchPhotos ?? [photo]) {
            p.humanTags = tags
            p.project = proj
        }
        photo.labelImageData = labelImage?.jpegData(compressionQuality: 0.85)
        try? modelContext.save()
        finish()
    }

    private func finish() {
        onDone()
        // In a sequential run, onDone advances to the next photo and the host
        // keeps the cover up; otherwise clear the presentation.
        if progress == nil { dismiss() }
    }
}

/// Drives a "one by one" tagging run over a queue of photos: shows each in turn,
/// advancing on Save/Skip, and offers the previous photo's tags for reuse.
struct SequentialTagView: View {
    let queue: [Photo]
    var onFinished: () -> Void
    @State private var index = 0
    @State private var previousTags: HumanTags?
    @State private var previousProject: String?

    var body: some View {
        Group {
            if index < queue.count {
                let photo = queue[index]
                TagSheetView(photo: photo,
                             previousTags: previousTags,
                             previousProject: previousProject,
                             progress: (index + 1, queue.count),
                             onExit: { index = queue.count },
                             onDone: {
                                if photo.humanTags.type != nil {
                                    previousTags = photo.humanTags
                                    previousProject = photo.project
                                }
                                index += 1
                             })
                    .id(photo.id)   // fresh tag state for each photo
            } else {
                Color.clear.onAppear { onFinished() }
            }
        }
    }
}

/// A single selectable tag button.
struct TagChip: View {
    let label: String
    let symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 17))
                }
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: symbol == nil ? 44 : 60)
            .background(selected ? Palette.coral.opacity(0.16) : Palette.tile)
            .foregroundStyle(selected ? Palette.coral : Palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Palette.coral : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
