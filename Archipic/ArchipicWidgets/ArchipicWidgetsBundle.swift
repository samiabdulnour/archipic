import WidgetKit
import SwiftUI

@main
struct ArchipicWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ArchiveLaunchWidget()
        if #available(iOS 18.0, *) {
            ArchipicWidgetsControl()
        }
    }
}
