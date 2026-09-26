import SwiftUI
import CloudKit
import CoreData

/// Surfaces iCloud sync state for the Settings screen: whether the iCloud
/// account is usable, whether a sync is in progress, and when it last finished.
/// Listens to the CloudKit-mirroring events SwiftData posts under the hood.
@Observable
final class SyncMonitor {
    enum Account { case checking, available, noAccount, restricted, error }

    var account: Account = .checking
    var isSyncing = false
    var lastSync: Date?
    var lastError: String?

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            if event.endDate == nil {
                self.isSyncing = true
            } else {
                self.isSyncing = false
                self.lastSync = event.endDate
                self.lastError = event.succeeded ? nil : event.error?.localizedDescription
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Asks CloudKit whether the user's iCloud account is available.
    func refreshAccount() {
        CKContainer.default().accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil { self.account = .error; return }
                switch status {
                case .available:  self.account = .available
                case .noAccount:  self.account = .noAccount
                case .restricted: self.account = .restricted
                default:          self.account = .error
                }
            }
        }
    }
}
