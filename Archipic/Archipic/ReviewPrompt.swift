import SwiftUI
import StoreKit

/// Asks for an App Store review — but only at a genuine success moment (a Board
/// export, or saving a photo once the archive holds 20), at most once per app version, and only
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

    /// Archive size at which saving a tagged photo counts as a success moment.
    /// 20 (was 50) so someone who starts in a launch week can reach it within
    /// their first weeks of use; the 3-day and once-per-version gates still apply.
    static let photoMilestone = 20

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

/// The App Store listing, for the "Rate Archipic" and "Tell a colleague" rows in
/// Settings. Plain URLs with no campaign or tracking parameters.
enum AppStoreLink {
    static let listing = URL(string: "https://apps.apple.com/app/id6777989742")!
    /// Opens the listing straight on the "Write a Review" sheet.
    static let writeReview = URL(string: "https://apps.apple.com/app/id6777989742?action=write-review")!
}
