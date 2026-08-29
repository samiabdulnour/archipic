import Foundation

/// App-side of the "jump to camera" plumbing. The Lock Screen control + widgets
/// (in the widget extension) set a flag in the shared App Group; the app reads
/// it on becoming active and opens the camera. The matching writer lives in the
/// widget target (it can't share this file under Xcode's synchronized folders).
enum QuickCapture {
    static let appGroup = "group.com.samiabdulnour.archive"
    private static let pendingKey = "pendingOpenCamera"
    private static let projectKey = "pendingProject"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Returns true once if the camera was requested, then clears the flag.
    static func consumeCameraRequest() -> Bool {
        guard let d = defaults, d.bool(forKey: pendingKey) else { return false }
        d.set(false, forKey: pendingKey)
        return true
    }

    /// Request the camera from an in-app AppIntent (Shortcuts / Siri / Action
    /// Button), optionally filing captures into a project. Same flag the widget
    /// writes — not a second path.
    static func requestCamera(project: String? = nil) {
        guard let d = defaults else { return }
        d.set(true, forKey: pendingKey)
        let p = project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if p.isEmpty { d.removeObject(forKey: projectKey) } else { d.set(p, forKey: projectKey) }
    }

    /// The project the camera should pre-select, consumed once.
    static func consumeProject() -> String? {
        guard let d = defaults, let p = d.string(forKey: projectKey), !p.isEmpty else { return nil }
        d.removeObject(forKey: projectKey)
        return p
    }
}
