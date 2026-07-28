import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Quick-capture intent (writes the shared flag, then opens the app)

enum WidgetQuickCapture {
    static let appGroup = "group.com.samiabdulnour.archive"
    static let pendingKey = "pendingOpenCamera"
    static func requestCamera() {
        UserDefaults(suiteName: appGroup)?.set(true, forKey: pendingKey)
    }
}

/// Opens Archi.vé and jumps straight into the camera. Used by the launch widget
/// and the Lock Screen / Control Center control.
struct OpenCameraIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Camera"
    static var description = IntentDescription("Open Archi.vé and start capturing.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetQuickCapture.requestCamera()
        return .result()
    }
}

// MARK: - Launch widget (Home Screen small + Lock Screen circular)

let archiveCoral = Color(red: 244 / 255, green: 78 / 255, blue: 72 / 255)

struct LaunchEntry: TimelineEntry { let date: Date }

struct LaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry { LaunchEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        completion(LaunchEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        completion(Timeline(entries: [LaunchEntry(date: .now)], policy: .never))
    }
}

struct LaunchWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Button(intent: OpenCameraIntent()) {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    // The app mark (dash-dot ring + disc); template so it takes the
                    // Lock Screen's monochrome tint.
                    Image("ArchiveMark")
                        .renderingMode(.template)
                        .resizable().scaledToFit()
                        .padding(7)
                }
            default:
                // The app mark in white on the coral container — mirrors the icon.
                Image("ArchiveMark")
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .frame(width: 92, height: 92)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ArchiveLaunchWidget: Widget {
    let kind = "ArchiveLaunch"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LaunchProvider()) { _ in
            LaunchWidgetView()
                .containerBackground(archiveCoral, for: .widget)
        }
        .configurationDisplayName("Capture")
        .description("Open Archi.vé straight into the camera.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
