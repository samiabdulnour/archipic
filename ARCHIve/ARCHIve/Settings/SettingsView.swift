import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// App settings, mirroring the old web app: Projects, Appearance, Capture flow
/// steps, Custom materials, and the How-to guide.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Photo.createdAt, order: .reverse) private var photos: [Photo]

    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("launchScreen") private var launchScreen = "camera"
    @AppStorage("customProjects") private var customProjectsRaw = ""
    @AppStorage("autoSuggestTags") private var autoSuggestTags = true

    @State private var newProject = ""

    private var derivedProjects: [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in photos { if let n = p.project, !n.isEmpty, seen.insert(n).inserted { out.append(n) } }
        return out
    }
    private var allProjects: [String] {
        (Set(derivedProjects).union(Settings.list(customProjectsRaw))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { launchBody } header: { header("On launch") } footer: {
                    Text("Choose what Archi.vé opens to.")
                }
                Section { projectsBody } header: { header("Projects") }
                Section { appearanceBody } header: { header("Appearance") }
                Section { captureStepsBody } header: { header("Capture flow steps") }
                Section {
                    Toggle("Suggest tags from the photo", isOn: $autoSuggestTags)
                } header: { header("Smart tagging") } footer: {
                    Text("Uses on-device image recognition (Apple Vision) to suggest a Kind when you tag. Nothing leaves your device; you always confirm.")
                }
                Section {
                    NavigationLink { HowToUseView() } label: { Text("How to use Archi.vé") }
                    NavigationLink { AboutView() } label: { Text("About Archi.vé") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Palette.coral)
        // Appearance is driven at the window level (Settings.applyAppearance),
        // so the sheet — and Auto — update correctly without a per-sheet
        // preferredColorScheme override.
        .onChange(of: appearance) { _, new in Settings.applyAppearance(new) }
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.caption.weight(.semibold)).tracking(1.2)
            .foregroundStyle(Palette.coral).textCase(.uppercase)
    }

    // MARK: Projects
    @ViewBuilder private var projectsBody: some View {
        if allProjects.isEmpty {
            Text("No projects yet.").foregroundStyle(.secondary)
        } else {
            ForEach(allProjects, id: \.self) { Text($0) }
                .onDelete { idx in
                    var custom = Settings.list(customProjectsRaw)
                    for i in idx { let name = allProjects[i]; custom.removeAll { $0 == name } }
                    customProjectsRaw = Settings.join(custom)
                }
        }
        HStack {
            TextField("New project name", text: $newProject)
            Button("Add") {
                let n = newProject.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                var custom = Settings.list(customProjectsRaw); custom.append(n)
                customProjectsRaw = Settings.join(custom); newProject = ""
            }.disabled(newProject.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: On launch
    private var launchBody: some View {
        Picker("On launch", selection: $launchScreen) {
            Label("Camera", systemImage: "camera.fill").tag("camera")
            Label("Gallery", systemImage: "square.grid.2x2").tag("gallery")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Appearance
    private var appearanceBody: some View {
        Picker("Appearance", selection: $appearance) {
            Text("Light").tag("light"); Text("Dark").tag("dark"); Text("Auto").tag("auto")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Capture flow steps
    private var captureStepsBody: some View {
        ForEach(TagVocab.types) { t in
            NavigationLink { FlowStepsView(flow: t.id, title: t.label) } label: { Text(t.label) }
        }
    }

}

/// Small helpers for the comma-separated @AppStorage lists, plus the resolved
/// colour scheme for the chosen appearance.
enum Settings {
    static func list(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
    static func join(_ items: [String]) -> String { items.joined(separator: "\n") }

    static func colorScheme(for appearance: String) -> ColorScheme? {
        switch appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }

    /// Apply the chosen appearance to every window so it takes effect app-wide
    /// (including sheets). `.unspecified` follows the system (Auto).
    static func applyAppearance(_ appearance: String) {
        let style: UIUserInterfaceStyle
        switch appearance {
        case "light": style = .light
        case "dark":  style = .dark
        default:      style = .unspecified
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows { window.overrideUserInterfaceStyle = style }
        }
    }
    static var customMaterials: [String] {
        list(UserDefaults.standard.string(forKey: "customMaterials") ?? "")
    }
    static var customProjects: [String] {
        list(UserDefaults.standard.string(forKey: "customProjects") ?? "")
    }

    /// Film grain on captured photos (and edited-look renders). Default on.
    /// The live camera preview never shows grain regardless.
    static var grainEnabled: Bool {
        UserDefaults.standard.object(forKey: "grainEnabled") as? Bool ?? true
    }

    // MARK: Capture flow steps

    /// (key, label) per Kind — the sections the user can show/hide.
    static func flowSteps(_ flow: String) -> [(String, String)] {
        switch flow {
        case "element": return [("element", "Element"), ("materiality", "Materiality"), ("colour", "Colour"),
                                ("authoryear", "Author & year"), ("note", "Note"), ("rating", "Rating")]
        case "graphic": return [("kind", "Kind"), ("details", "Details"), ("visual", "Visual"),
                                ("note", "Note"), ("rating", "Rating")]
        default:        return [("typology", "Typology"), ("concept", "Concept"), ("materiality", "Materiality"),
                                ("colour", "Colour"), ("authoryear", "Author & year"), ("note", "Note"), ("rating", "Rating")]
        }
    }
    /// Concept, Colour, Visual, Rating are off by default everywhere; Materiality
    /// is off by default for Buildings only (kept on for Elements). Rest on.
    static func flowDefault(_ flow: String, _ step: String) -> Bool {
        if step == "concept" || step == "colour" || step == "visual" || step == "rating" { return false }
        if step == "materiality" && flow == "building" { return false }
        return true
    }

    static func flowEnabled(_ flow: String, _ step: String) -> Bool {
        flowDict()["\(flow).\(step)"] ?? flowDefault(flow, step)
    }
    static func flowDict() -> [String: Bool] {
        let raw = UserDefaults.standard.string(forKey: "flowSteps") ?? ""
        return (try? JSONDecoder().decode([String: Bool].self, from: Data(raw.utf8))) ?? [:]
    }
}

/// Toggle which tagging sections appear for a Kind (the capture flow).
private struct FlowStepsView: View {
    let flow: String
    let title: String
    @AppStorage("flowSteps") private var raw = ""

    var body: some View {
        Form {
            Section {
                ForEach(Settings.flowSteps(flow), id: \.0) { step in
                    Toggle(step.1, isOn: binding(step.0))
                }
            } footer: {
                Text("Hidden sections are skipped while tagging. Kind/Typology/Element stay available.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Palette.coral)
    }

    private func binding(_ step: String) -> Binding<Bool> {
        Binding(
            get: { Settings.flowEnabled(flow, step) },
            set: { newVal in
                var d = Settings.flowDict()
                d["\(flow).\(step)"] = newVal
                raw = String(data: (try? JSONEncoder().encode(d)) ?? Data(), encoding: .utf8) ?? ""
            }
        )
    }
}
