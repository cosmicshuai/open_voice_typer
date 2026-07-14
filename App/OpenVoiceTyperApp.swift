import SwiftData
import SwiftUI

@main
struct OpenVoiceTyperApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: TranscriptRecord.self)
    }
}
