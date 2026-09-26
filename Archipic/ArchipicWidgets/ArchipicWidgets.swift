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

/// Opens Archipic and jumps straight into the camera. Used by the launch widget
/// and the Lock Screen / Control Center control.
struct OpenCameraIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Camera"
    static var description = IntentDescription("Open Archipic and start capturing.")
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
                    WidgetMark(color: .white).padding(8)
                }
            default:
                // The app mark in white on the coral container — mirrors the icon.
                WidgetMark(color: .white)
                    .frame(width: 96, height: 96)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The app mark — the App Store icon's dash-dot ring around a filled disc —
/// drawn as a shape so it always renders in the widget (no template-asset/tint
/// quirks). Fills its frame; `color` is explicit.
struct WidgetMark: View {
    var color: Color

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            // Exactly the capture button's proportions (ring 72 → lineWidth 1.6),
            // so the widget mark matches the in-app mark and the icon: a thin ring,
            // the icon's 15 long-dash-double-dot repeats, disc = 0.911 × ring.
            let lw = side * (1.6 / 72)
            let ring = side - lw                 // keep the round-capped stroke in bounds
            let disc = ring * 0.911
            let c = CGFloat.pi * ring
            let long = c * 9.75 / 360
            let dot  = c * 1.5  / 360
            let gap  = c * 3.75 / 360
            ZStack {
                Circle()
                    .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round,
                                                      dash: [long, gap, dot, gap, dot, gap]))
                    .frame(width: ring, height: ring)
                Circle().fill(color).frame(width: disc, height: disc)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
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
        .description("Open Archipic straight into the camera.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
