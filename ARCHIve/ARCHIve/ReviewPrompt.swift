import SwiftUI
import StoreKit

/// Asks for an App Store review — but only at a genuine success moment (a Board
/// export, or tagging the 50th photo), at most once per app version, and only
/// after the app has been in use for more than a few days. Never on launch and
/// never after an error.
///
/// `RequestReviewAction` (Apple's `@Environment(\.requestReview)`) already
/// rate-limits system-side; this adds our own conservative gate on top so the
/// prompt is rare and well-timed.
enum ReviewPrompt {
    private static let firstUseKey = "reviewFirstUseDate"
    private static let promptedVersionKey = "reviewPromptedVersion"
    private static let minDaysOfUse = 3.0

    private static var defaults: UserDefaults { .standard }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Stamp the first time the app was opened, so the "a few days" gate has a
    /// start point. Safe to call on every launch — only the first write sticks.
    static func noteFirstUseIfNeeded() {
        if defaults.object(forKey: firstUseKey) == nil {
            defaults.set(Date(), forKey: firstUseKey)
        }
    }

    /// May we prompt right now? Enough days of use have passed and we haven't
    /// already prompted on this version.
    private static var eligible: Bool {
        guard let first = defaults.object(forKey: firstUseKey) as? Date else { return false }
        guard Date().timeIntervalSince(first) >= minDaysOfUse * 86_400 else { return false }
        return defaults.string(forKey: promptedVersionKey) != appVersion
    }

    /// Ask for a review at a success moment, if eligible. Records this version as
    /// prompted so it can never fire twice on the same version.
    @MainActor
    static func ask(_ request: RequestReviewAction) {
        guard eligible else { return }
        defaults.set(appVersion, forKey: promptedVersionKey)
        request()
    }
}
