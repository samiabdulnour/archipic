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

    /// A pending "open the camera" request, with the project it was made for.
    struct Request { let project: String? }

    /// Returns the pending request once, clearing BOTH keys together. They must be
    /// consumed atomically: leaving the project behind meant a later, unrelated
    /// camera open (toolbar, widget, launch preference) silently filed its shot
    /// into a project the user chose minutes ago.
    static func consumeCameraRequest() -> Request? {
        guard let d = defaults, d.bool(forKey: pendingKey) else { return nil }
        d.set(false, forKey: pendingKey)
        let project = d.string(forKey: projectKey)
        d.removeObject(forKey: projectKey)
        return Request(project: (project?.isEmpty == false) ? project : nil)
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

}
