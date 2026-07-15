import SwiftUI

@main
struct OpenVoiceTyperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Open Voice Typer")
                    .font(.title2.bold())
                Text("Voice input, polished by your own AI keys.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Open Voice Typer")
        }
    }
}

#Preview {
    ContentView()
}
