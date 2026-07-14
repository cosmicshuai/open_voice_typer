import Foundation
import SwiftData

/// One completed dictation, kept locally (local-first, never synced).
@Model
final class TranscriptRecord {
    var id: UUID = UUID()
    var rawText: String = ""
    var polishedText: String = ""
    var styleID: String = ""
    var source: String = Source.app.rawValue
    var createdAt: Date = Date.now

    enum Source: String {
        case app
        case keyboard
    }

    init(rawText: String, polishedText: String, styleID: String, source: Source) {
        self.id = UUID()
        self.rawText = rawText
        self.polishedText = polishedText
        self.styleID = styleID
        self.source = source.rawValue
        self.createdAt = .now
    }

    var styleName: String {
        SharedCatalog.style(id: styleID)?.name ?? styleID
    }
}
