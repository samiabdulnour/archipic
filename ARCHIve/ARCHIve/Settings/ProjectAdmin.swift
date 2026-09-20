import SwiftUI
import SwiftData

/// Renaming and deleting projects.
///
/// A project is not a record of its own. It is only the `project` string on each
/// photo, plus any names the owner typed into Settings ahead of time. So both
/// operations are a sweep over the photos that carry the name — there is no
/// separate "project" to edit, and nothing here touches the data model.
///
/// Neither operation ever deletes a photo. Deleting a project only clears the
/// label; the photos stay in the archive, unfiled.
enum ProjectAdmin {
    /// How many photos are filed under `name`.
    static func count(_ name: String, in photos: [Photo]) -> Int {
        photos.reduce(0) { $0 + ($1.project == name ? 1 : 0) }
    }

    /// Re-label every photo filed under `old` as `new`. Renaming onto a name that
    /// already exists simply merges the two projects. Returns the name actually
    /// applied (trimmed), or nil when there was nothing to do.
    @MainActor @discardableResult
    static func rename(_ old: String, to new: String,
                       photos: [Photo], context: ModelContext) -> String? {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != old else { return nil }
        relabel(old, as: name, photos: photos, context: context)
        updateCustomList { list in
            // Keep the pre-typed list in step, without creating a duplicate when
            // the new name was already on it.
            var out: [String] = []
            for item in list.map({ $0 == old ? name : $0 }) where !out.contains(item) { out.append(item) }
            return out
        }
        return name
    }

    /// Remove the project label from every photo that carries it, and drop the
    /// name from the pre-typed list. The photos themselves are untouched.
    @MainActor
    static func delete(_ name: String, photos: [Photo], context: ModelContext) {
        relabel(name, as: nil, photos: photos, context: context)
        updateCustomList { $0.filter { $0 != name } }
    }

    // MARK: Internals

    @MainActor
    private static func relabel(_ old: String, as new: String?,
                                photos: [Photo], context: ModelContext) {
        // `modelContext != nil` skips a photo deleted a moment ago: writing to a
        // deleted SwiftData model raises an exception that can't be caught.
        for p in photos where p.project == old && p.modelContext != nil { p.project = new }
        do { try context.save() } catch { context.rollback() }   // all or nothing
    }

    private static func updateCustomList(_ transform: ([String]) -> [String]) {
        let d = UserDefaults.standard
        let current = Settings.list(d.string(forKey: "customProjects") ?? "")
        d.set(Settings.join(transform(current)), forKey: "customProjects")
    }
}

/// The rename prompt and the delete confirmation, shared by every place a project
/// can be managed (Settings, and the Project lens). Set `renaming` or `deleting`
/// to a project name to raise the matching dialog.
struct ProjectAdminDialogs: ViewModifier {
    @Binding var renaming: String?
    @Binding var deleting: String?
    let photos: [Photo]
    /// Called after a change with the old name and the new one (nil = deleted), so
    /// the host can fix up anything still pointing at the old name, e.g. a filter.
    var onChange: (_ old: String, _ new: String?) -> Void = { _, _ in }

    @Environment(\.modelContext) private var modelContext
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: renaming) { _, name in draft = name ?? "" }
            .alert("Rename project", isPresented: isPresent($renaming), presenting: renaming) { old in
                TextField("Project name", text: $draft)
                    .textInputAutocapitalization(.words)
                Button("Rename") {
                    if let applied = ProjectAdmin.rename(old, to: draft, photos: photos, context: modelContext) {
                        onChange(old, applied)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { old in
                Text("Every photo filed under “\(old)” moves to the new name.")
            }
            .alert("Delete project?", isPresented: isPresent($deleting), presenting: deleting) { name in
                Button("Delete", role: .destructive) {
                    ProjectAdmin.delete(name, photos: photos, context: modelContext)
                    onChange(name, nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: { name in
                let n = ProjectAdmin.count(name, in: photos)
                let filed = n == 1 ? "1 photo is filed" : "\(n) photos are filed"
                Text(n == 0
                     ? "“\(name)” has no photos."
                     : "\(filed) under “\(name)”. Nothing is deleted from your archive — only the project label is removed.")
            }
    }

    /// A Bool binding over an optional: true while it holds a value.
    private func isPresent(_ value: Binding<String?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil },
                set: { if !$0 { value.wrappedValue = nil } })
    }
}

extension View {
    func projectAdminDialogs(renaming: Binding<String?>, deleting: Binding<String?>, photos: [Photo],
                             onChange: @escaping (_ old: String, _ new: String?) -> Void = { _, _ in }) -> some View {
        modifier(ProjectAdminDialogs(renaming: renaming, deleting: deleting, photos: photos, onChange: onChange))
    }
}
