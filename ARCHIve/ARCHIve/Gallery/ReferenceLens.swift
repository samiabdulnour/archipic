import SwiftUI

/// The Reference lens — browse the archive by what's in the photos.
/// Outer: All / Building / Element / Graphic. Building & Element have inner
/// dimensions; each value is a row (count + thumbnail strip) that drills into
/// a hero grid. Mirrors the web app's row-index browser.
struct ReferenceLens: View {
    let photos: [Photo]
    @Binding var gridCols: Int

    @Environment(\.modelContext) private var modelContext
    @State private var outer = "all"
    @State private var buildingDim = "typology"
    @State private var elementDim = "element"
    @State private var pinchBase: Int?

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            PillToggle(selection: $outer,
                       options: [PillOption(value: "all", label: "All")]
                            + TagVocab.types.map { PillOption(value: $0.id, label: $0.label) })
                .padding(.horizontal, 12).padding(.bottom, 8)

            switch outer {
            case "building":
                innerPicker($buildingDim, ["typology": "Typology", "room": "Room",
                                           "concept": "Concept", "material": "Material"],
                            order: ["typology", "room", "concept", "material"])
                rowIndex(buildingGroups)
            case "element":
                innerPicker($elementDim, ["element": "Element", "material": "Material"],
                            order: ["element", "material"])
                rowIndex(elementGroups)
            case "graphic":
                rowIndex(graphicGroups)
            default:
                grid(photos.filter { $0.humanTags.type != nil })
            }
        }
    }

    // MARK: Inner picker

    private func innerPicker(_ sel: Binding<String>, _ labels: [String: String], order: [String]) -> some View {
        PillToggle(selection: sel, options: order.map { PillOption(value: $0, label: labels[$0] ?? $0) })
            .padding(.horizontal, 12).padding(.bottom, 8)
    }

    // MARK: Groupings  (label, photos) sorted by count desc

    private var buildingGroups: [(String, [Photo])] {
        let b = photos.filter { $0.humanTags.type == "building" }
        switch buildingDim {
        case "room":     return grouped(b) { $0.humanTags.room.map { [$0.capitalized] } ?? [] }
        case "concept":  return grouped(b) { $0.humanTags.concepts.map { $0.capitalized } }
        case "material": return grouped(b) { $0.humanTags.materials }
        default:         return grouped(b) { $0.humanTags.typology.map { [$0] } ?? [] }
        }
    }
    private var elementGroups: [(String, [Photo])] {
        let e = photos.filter { $0.humanTags.type == "element" }
        switch elementDim {
        case "material": return grouped(e) { $0.humanTags.materials }
        default:         return grouped(e) { $0.humanTags.element.map { [$0] } ?? [] }
        }
    }
    private var graphicGroups: [(String, [Photo])] {
        grouped(photos.filter { $0.humanTags.type == "graphic" }) {
            $0.humanTags.graphicKind.map { [$0.capitalized] } ?? []
        }
    }

    private func grouped(_ items: [Photo], _ keys: (Photo) -> [String]) -> [(String, [Photo])] {
        var map: [String: [Photo]] = [:]
        for p in items { for k in keys(p) where !k.isEmpty { map[k, default: []].append(p) } }
        return map.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
    }


    // MARK: Row index + hero

    private func rowIndex(_ groups: [(String, [Photo])]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if groups.isEmpty {
                    Text("Nothing here yet.").foregroundStyle(Palette.ink3)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink {
                            CategoryHero(title: group.0, photos: group.1)
                        } label: {
                            HStack {
                                Text(group.0).font(.headline).foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(group.1.count)").font(.subheadline).foregroundStyle(Palette.ink3)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.ink3)
                            }
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(group.1.prefix(12)) { p in
                                    NavigationLink(value: p) {
                                        PhotoThumbnail(photo: p).frame(width: 96, height: 96).clipped()
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func grid(_ items: [Photo]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: gridCols)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items) { p in
                    NavigationLink(value: p) {
                        PhotoThumbnail(photo: p).aspectRatio(1, contentMode: .fill).clipped()
                            .overlay { if p.isFavorite { Rectangle().strokeBorder(Color.red, lineWidth: 2) } }
                            .overlay(alignment: .topLeading) { TileBadges(photo: p).padding(4) }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { p.isFavorite.toggle(); try? modelContext.save() } label: {
                            Label(p.isFavorite ? "Remove Favourite" : "Favourite",
                                  systemImage: p.isFavorite ? "heart.slash" : "heart")
                        }
                        Divider()
                        Button(role: .destructive) {
                            modelContext.delete(p); try? modelContext.save()
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: gridCols)
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if pinchBase == nil { pinchBase = gridCols }
                    let base = pinchBase ?? gridCols
                    let steps = Int((value.magnification - 1) * 5)
                    gridCols = min(8, max(1, base - steps))
                }
                .onEnded { _ in pinchBase = nil }
        )
    }
}

/// Drill-down: all photos for one category, grouped by year (newest first).
private struct CategoryHero: View {
    let title: String
    let photos: [Photo]
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var byYear: [(Int, [Photo])] {
        let cal = Calendar.current
        let map = Dictionary(grouping: photos) { cal.component(.year, from: $0.createdAt) }
        return map.sorted { $0.key > $1.key }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                ForEach(byYear, id: \.0) { year, items in
                    Section {
                        LazyVGrid(columns: cols, spacing: 2) {
                            ForEach(items) { p in
                                NavigationLink(value: p) {
                                    PhotoThumbnail(photo: p).aspectRatio(1, contentMode: .fill).clipped()
                                        .overlay { if p.isFavorite { Rectangle().strokeBorder(Color.red, lineWidth: 2) } }
                                }.buttonStyle(.plain)
                            }
                        }
                    } header: {
                        HStack {
                            Text(String(year)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(items.count)").foregroundStyle(Palette.ink3)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Palette.paper)
                    }
                }
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
