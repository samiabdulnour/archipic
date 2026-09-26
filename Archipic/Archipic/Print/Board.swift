import Foundation
import SwiftData

/// A saved board — a named, ordered collection of photos with a chosen layout.
/// CloudKit-safe: every property has a default and there's no `.unique`. Photo
/// membership is stored as an ordered list of photo ids (JSON), not a SwiftData
/// relationship, to stay simple and portable (and survive photo deletes — missing
/// ids are just skipped when rendering).
@Model
final class Board: Identifiable {
    var id: String = ""
    var title: String = ""
    var layoutRaw: String = "posterB1"
    var photoIDsData: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: String = UUID().uuidString, title: String = "",
         layout: BoardLayout = .posterB1, photoIDs: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.layoutRaw = layout.rawValue
        self.photoIDsData = (try? JSONEncoder().encode(photoIDs)) ?? Data()
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var layout: BoardLayout {
        get { BoardLayout(rawValue: layoutRaw) ?? .posterB1 }
        set { layoutRaw = newValue.rawValue }
    }
    var photoIDs: [String] {
        get { (try? JSONDecoder().decode([String].self, from: photoIDsData)) ?? [] }
        set { photoIDsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
