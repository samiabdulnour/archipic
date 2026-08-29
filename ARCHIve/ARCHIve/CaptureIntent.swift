import AppIntents

/// Capture a reference straight from Shortcuts, Siri, Spotlight or the Action
/// Button — opens Archipic into the camera, optionally filing captures into a
/// project. It shares the App Group "jump to camera" flag with the widget /
/// Control Centre control (`QuickCapture`), so there's one capture path, not two.
struct CaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture in Archipic"
    static var description = IntentDescription("Open Archipic and start capturing, optionally into a project.")
    static var openAppWhenRun = true

    @Parameter(title: "Project",
               description: "File the captures into this project (leave empty for unfiled).")
    var project: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCapture.requestCamera(project: project)
        return .result()
    }
}

/// Surfaces the capture intent to Siri and Spotlight, and makes it assignable to
/// the Action Button. Phrases use the app's display name automatically.
struct ArchipicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "New reference in \(.applicationName)",
                "Snap a reference in \(.applicationName)",
            ],
            shortTitle: "Capture",
            systemImageName: "camera"
        )
    }
}
