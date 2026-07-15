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
    /// Model that produced `polishedText` ("on-device", "gpt-4o-mini", …).
    var engineName: String = ""
    /// Length of the recorded audio; 0 for re-polished entries' unknown originals.
    var audioSeconds: Double = 0

    enum Source: String {
        case app
        case keyboard
    }

    init(
        rawText: String,
        polishedText: String,
        styleID: String,
        source: Source,
        engineName: String = "",
        audioSeconds: Double = 0
    ) {
        self.id = UUID()
        self.rawText = rawText
        self.polishedText = polishedText
        self.styleID = styleID
        self.source = source.rawValue
        self.createdAt = .now
        self.engineName = engineName
        self.audioSeconds = audioSeconds
    }

    var styleName: String {
        SharedCatalog.style(id: styleID)?.name ?? styleID
    }
}
