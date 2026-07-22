import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        tabs
            .tint(.appAccent)
            // Opening the app IS the session setup: whenever it comes to the
            // foreground with mic permission already granted, the keyboard
            // session starts (or resumes) by itself.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await SessionController.shared.autoStartIfPossible() }
                }
            }
            .onAppear {
                if CommandLine.arguments.contains("--reset-onboarding") {
                    hasCompletedOnboarding = false
                    UserDefaults.standard.set(0, forKey: OnboardingView.pageKey)
                }
                if CommandLine.arguments.contains("--skip-onboarding") {
                    hasCompletedOnboarding = true
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
