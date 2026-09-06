import SwiftUI
import SwiftData
import PhotosUI

/// The editable tagging form — type picker, the per-Kind sections (Building /
/// Element / Graphic), and the extras. Shared by `TagSheetView` (post-capture,
/// committed on Save) and `PhotoDetailView` (inline, auto-saving). It edits the
/// bound `tags` / `project` / `labelImage`; the host decides when to persist.
struct TagForm: View {
    @Binding var tags: HumanTags
    @Binding var project: String
    @Binding var labelImage: UIImage?
    /// An existing library photo → the label is *selected* from Photos; a
    /// camera shot → the label is *shot* with the camera.
    var isLibraryPhoto: Bool

    @Query private var allPhotos: [Photo]
    @State private var showLabelCamera = false
    @State private var labelPickerItem: PhotosPickerItem?
    @State private var showFullscreenLabel = false
    @State private var placeSuggestions: [String] = []
    @State private var tagSearch = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    private var flow: String { tags.type ?? "building" }
    private func enabled(_ step: String) -> Bool { Settings.flowEnabled(flow, step) }

    private var existingProjects: [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in allPhotos {
            guard let name = p.project, !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name); out.append(name)
        }
        return Set(out).union(Settings.customProjects).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                typePicker
                searchToggle
            }
            if searching {
                tagSearchField
                tagSearchResults
            } else {
                switch tags.type {
                case "building": buildingSections
                case "element":  elementSections
                case "graphic":  graphicSections
                default:
                    Text("Pick a category above.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
                if tags.type != nil { extrasSection }
            }
        }
        .onChange(of: labelPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    labelImage = UIImage(data: data)
                }
                labelPickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showLabelCamera) {
            ImagePicker { data in labelImage = UIImage(data: data) }
                .ignoresSafeArea()
        }
        .onAppear { if placeSuggestions.isEmpty { placeSuggestions = recentPlaces() } }
    }

    /// Distinct cities the owner has typed before — offered as one-tap chips so a
    /// trip's photos reuse the same place without retyping. Computed once on
    /// appear (decoding every photo's tags) to keep the text field responsive.
    private func recentPlaces() -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in allPhotos {
            let name = (p.humanTags.place ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name); out.append(name)
        }
        return out.sorted()
    }

    // MARK: Tag search — a small button reveals a search over the whole
    // vocabulary, for when the right category isn't obvious (e.g. a fence).

    private var searchToggle: some View {
        Button {
            if searching {
                searching = false; tagSearch = ""; searchFocused = false
            } else {
                searching = true; searchFocused = true
            }
        } label: {
            Image(systemName: searching ? "xmark" : "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 44)
                .foregroundStyle(searching ? Color(white: 0.13) : Palette.ink)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(searching ? Palette.lemon : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(searching ? "Close tag search" : "Find a tag")
    }

    private var tagSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Palette.ink3)
            TextField("Find a tag (e.g. Fence)", text: $tagSearch)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(size: 15))
                .focused($searchFocused)
                .submitLabel(.done)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Palette.paperElev, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5))
    }

    @ViewBuilder private var tagSearchResults: some View {
        let q = tagSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            Text("Type to find any tag — element, typology, material…")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
        } else {
            let hits = TagVocab.search(tagSearch)
            if hits.isEmpty {
                Text("No matching tag. The vocabulary is a fixed set — try a broader word, or pick a category above.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(hits) { hit in
                        Button { apply(hit) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: hit.symbol).font(.system(size: 15)).frame(width: 24)
                                    .foregroundStyle(Palette.ink2)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(LocalizedStringKey(hit.label)).font(.system(size: 15)).foregroundStyle(Palette.ink)
                                    Text(hit.context).font(.caption).foregroundStyle(Palette.ink3)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.left").font(.system(size: 12)).foregroundStyle(Palette.ink3)
                            }
                            .padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if hit.id != hits.last?.id { Divider() }
                    }
                }
            }
        }
    }

    /// Apply a found tag — sets its canonical value and the matching Kind, then
    /// closes the search so the normal form returns with the tag selected.
    private func apply(_ hit: TagVocab.Hit) {
        TagVocab.apply(hit, to: &tags)
        searching = false; tagSearch = ""; searchFocused = false
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Building / Element / Graphic — custom toggle matching the tag buttons:
    /// boxless, filled icon + label, with a coral squircle highlight on the active one.
    private var typePicker: some View {
        HStack(spacing: 4) {
            ForEach(TagVocab.types) { t in
                let on = tags.type == t.id
                Button { tags.type = t.id } label: {
                    HStack(spacing: 7) {
                        Image(systemName: t.symbol).font(.system(size: 15)).symbolVariant(.fill)
                        Text(LocalizedStringKey(t.label)).font(.system(size: 14, weight: on ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(on ? Palette.lemon : .clear))
                    .foregroundStyle(on ? Color(white: 0.13) : Palette.ink)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: tags.type)
    }

    // MARK: Building

    @ViewBuilder private var buildingSections: some View {
        if enabled("typology") {
            typologySection
            if let typ = tags.typology, typ != "Landscape" {
                let rooms = TagVocab.roomsFor(typ)
                if !rooms.isEmpty { roomSection(rooms) }
            }
        }
        if enabled("concept") { conceptSection }
        if enabled("materiality") { materialitySection }
        if enabled("colour") { colorSection }
    }

    // MARK: Element

    @ViewBuilder private var elementSections: some View {
        if enabled("element") {
            tileSection("Element") {
                ForEach(TagVocab.elementCategories, id: \.category) { cat in
                    CompactTile(label: cat.category, selected: tags.elementCategory == cat.category) {
                        symbolArt("elementcat", cat.category)
                    } action: {
                        if tags.elementCategory == cat.category { tags.elementCategory = nil; tags.element = nil }
                        else { tags.elementCategory = cat.category; tags.element = nil }
                    }
                }
            }
            if let cat = tags.elementCategory {
                tileSection(cat) {
                    ForEach(TagVocab.elementItems(for: cat), id: \.self) { sub in
                        CompactTile(label: sub, selected: tags.element == sub) {
                            symbolArt("elementsub", sub)
                        } action: { tags.element = (tags.element == sub) ? nil : sub }
                    }
                }
            }
        }
        // Finish → Paint swaps Materiality for Colour (web behaviour).
        if tags.element == "Paint" {
            colorSection
        } else {
            if enabled("materiality") { materialitySection }
            if enabled("colour") { colorSection }
        }
    }

    // MARK: Materiality (shared by Building + Element)

    private var materialitySection: some View {
        tileSection("Materiality") {
            ForEach(TagVocab.materials + Settings.customMaterials, id: \.self) { m in
                CompactTile(label: m, selected: tags.materials.contains(m)) {
                    symbolArt("material", m)
                } action: {
                    if let i = tags.materials.firstIndex(of: m) { tags.materials.remove(at: i) }
                    else { tags.materials.append(m) }
                }
            }
        }
    }

    // MARK: Colour (shared by Building + Element)

    private var colorSection: some View {
        tileSection("Colour") {
            ForEach(TagVocab.colors, id: \.id) { c in
                CompactTile(label: c.label, selected: tags.colors.contains(c.id)) {
                    RoundedRectangle(cornerRadius: 5).fill(Color(hex: c.hex))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.hairline, lineWidth: 0.5))
                } action: {
                    if let i = tags.colors.firstIndex(of: c.id) { tags.colors.remove(at: i) }
                    else { tags.colors.append(c.id) }
                }
            }
        }
    }

    private var tileColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    }

    // MARK: Graphic

    @ViewBuilder private var graphicSections: some View {
        if enabled("kind") { graphicKindSection }
        if enabled("details") { graphicDetailSection }
        if enabled("visual") { visualSection }
    }

    /// Per-kind detail fields. Plus a "Capture/Select label" shortcut: snap (or
    /// pick) the wall placard instead of typing the title/artist by hand.
    @ViewBuilder private var graphicDetailSection: some View {
        let fields = TagVocab.graphicFields(for: tags.graphicKind)
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Details")
                labelCaptureRow
                ForEach(fields, id: \.0) { field in
                    TextField(field.1, text: binding(for: field.0))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    @ViewBuilder private var labelCaptureRow: some View {
        if let img = labelImage {
            HStack(spacing: 12) {
                Button { showFullscreenLabel = true } label: {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Label added").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                    Text("Tap to view").font(.caption).foregroundStyle(Palette.ink3)
                }
                Spacer()
                if isLibraryPhoto {
                    PhotosPicker(selection: $labelPickerItem, matching: .images) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16))
                    }
                } else {
                    Button { showLabelCamera = true } label: {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16))
                    }
                }
                Button(role: .destructive) { labelImage = nil } label: {
                    Image(systemName: "trash").font(.system(size: 16))
                }
            }
            .fullScreenCover(isPresented: $showFullscreenLabel) {
                IntrospectionView(image: labelImage) { showFullscreenLabel = false }
            }
        } else if isLibraryPhoto {
            // Tagging from the library: pick the label from the library too.
            PhotosPicker(selection: $labelPickerItem, matching: .images) {
                Label("Select label", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.tile))
                    .foregroundStyle(Palette.ink)
            }
        } else {
            Button { showLabelCamera = true } label: {
                Label("Capture label", systemImage: "text.viewfinder")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.tile))
                    .foregroundStyle(Palette.ink)
            }
            .buttonStyle(.plain)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        switch key {
        case "title":   return strBinding(\.title)
        case "creator": return strBinding(\.creator)
        case "year":    return strBinding(\.year)
        case "source":  return strBinding(\.source)
        case "name":    return strBinding(\.contactName)
        case "company": return strBinding(\.contactCompany)
        default:        return strBinding(\.title)
        }
    }
    private func strBinding(_ kp: WritableKeyPath<HumanTags, String?>) -> Binding<String> {
        Binding(get: { tags[keyPath: kp] ?? "" },
                set: { tags[keyPath: kp] = $0.isEmpty ? nil : $0 })
    }

    // MARK: Illustrated sections

    private func symbolArt(_ group: String, _ id: String) -> some View {
        Image(systemName: TagVocab.symbol(group, id))
            .font(.system(size: 21, weight: .regular))
            .symbolVariant(.fill)   // filled SF Symbols — more graphic, App Store-like
    }

    private func tileSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            LazyVGrid(columns: tileColumns, spacing: 6, content: content)
        }
    }

    private func roomSection(_ rooms: [TagOption]) -> some View {
        tileSection("Room") {
            ForEach(rooms) { r in
                CompactTile(label: r.label, selected: tags.room == r.id) {
                    symbolArt("room", r.id)
                } action: { tags.room = (tags.room == r.id) ? nil : r.id }
            }
        }
    }

    private var conceptSection: some View {
        tileSection("Concept") {
            ForEach(TagVocab.concepts) { c in
                CompactTile(label: c.label, selected: tags.concepts.contains(c.id)) {
                    symbolArt("concept", c.id)
                } action: {
                    if let i = tags.concepts.firstIndex(of: c.id) { tags.concepts.remove(at: i) }
                    else { tags.concepts.append(c.id) }
                }
            }
        }
    }

    private var typologySection: some View {
        tileSection("Typology") {
            ForEach(TagVocab.typology, id: \.self) { ty in
                CompactTile(label: ty, selected: tags.typology == ty) {
                    symbolArt("typology", ty)
                } action: { tags.typology = (tags.typology == ty) ? nil : ty }
            }
        }
    }

    private var graphicKindSection: some View {
        tileSection("Kind") {
            ForEach(TagVocab.graphicKinds) { k in
                CompactTile(label: k.label, selected: tags.graphicKind == k.id) {
                    symbolArt("graphic", k.id)
                } action: { tags.graphicKind = (tags.graphicKind == k.id) ? nil : k.id }
            }
        }
    }

    private var visualSection: some View {
        tileSection("Visual") {
            ForEach(TagVocab.visual, id: \.self) { v in
                CompactTile(label: v, selected: tags.visual.contains(v)) {
                    symbolArt("visual", v)
                } action: {
                    if let i = tags.visual.firstIndex(of: v) { tags.visual.remove(at: i) }
                    else { tags.visual.append(v) }
                }
            }
        }
    }

    // MARK: Extras

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 2)
            if enabled("rating") { ratingRow }
            if tags.type != "graphic" && enabled("authoryear") {
                HStack(spacing: 8) {
                    TextField("Author", text: strBinding(\.creator))
                        .textFieldStyle(.roundedBorder)
                    TextField("Year", text: strBinding(\.year))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 78)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numbersAndPunctuation)
                }
            }
            if enabled("note") {
                TextField("Note", text: Binding(
                    get: { tags.note ?? "" },
                    set: { tags.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("Keywords (comma separated)", text: Binding(
                get: { tags.keywords.joined(separator: ", ") },
                set: { tags.keywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            placeSection
            projectSection
        }
    }

    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Place / city", text: Binding(
                get: { tags.place ?? "" },
                set: { tags.place = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            if !placeSuggestions.isEmpty {
                chipGrid(placeSuggestions.map { ($0, $0, nil as String?) }) { id in
                    tags.place == id
                } toggle: { id in
                    tags.place = (tags.place == id) ? nil : id
                }
            }
        }
    }

    private var ratingRow: some View {
        HStack {
            Text("Rating").foregroundStyle(Palette.ink3)
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    let filled = (tags.rating ?? 0) >= i
                    Button {
                        tags.rating = (tags.rating == i) ? nil : i
                    } label: {
                        Image(systemName: filled ? "star.fill" : "star")
                            .font(.system(size: 17))
                            .foregroundStyle(filled ? Palette.coral : Palette.ink3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.paperElev))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.hairline, lineWidth: 0.5))
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Project", text: $project)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            if !existingProjects.isEmpty {
                chipGrid(existingProjects.map { ($0, $0, nil as String?) }) { id in
                    project == id
                } toggle: { id in
                    project = (project == id) ? "" : id
                }
            }
        }
    }

    // MARK: Reusable builders

    private func sectionLabel(_ t: String) -> some View {
        // Section titles are English identifiers (also stored keys elsewhere);
        // localize only the display.
        Text(LocalizedStringKey(t)).font(.headline)
    }

    private func chipGrid(_ options: [(String, String, String?)],
                          isSelected: @escaping (String) -> Bool,
                          toggle: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(options, id: \.0) { opt in
                TagChip(label: opt.1, symbol: opt.2, selected: isSelected(opt.0)) { toggle(opt.0) }
            }
        }
    }
}
