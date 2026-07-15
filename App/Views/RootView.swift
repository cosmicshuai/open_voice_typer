import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        tabs
            .tint(.appAccent)
            .onAppear {
                if CommandLine.arguments.contains("--reset-onboarding") {
                    hasCompletedOnboarding = false
                }
                showOnboarding = !hasCompletedOnboarding
            }
            .fullScreenCover(isPresented: $showOnboarding, onDismiss: {
                hasCompletedOnboarding = true
            }) {
                OnboardingView(isPresented: $showOnboarding)
                    .tint(.appAccent)
            }
    }

    private var tabs: some View {
        TabView {
            Tab("Dictate", systemImage: "mic.fill") {
                HomeView()
            }
            Tab("History", systemImage: "clock") {
                HistoryView()
            }
            Tab("Templates", systemImage: "wand.and.stars") {
                TemplatesView()
            }
            Tab("Dictionary", systemImage: "character.book.closed") {
                DictionaryView()
            }
            Tab("Settings", systemImage: "gearshape") {
                ConfigurationView()
            }
        }
    }
}

#Preview {
    RootView()
}
