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
            //
            // Both triggers are needed. `onChange` fires on a *transition*, so
            // it covers a return from the background but can miss a launch
            // entirely — a cold start may already be `.active` by the time this
            // view first renders, and then nothing observes a change. That is
            // precisely the case the keyboard's "Open Voice Typer" link hits:
            // after an idle auto-end the app has usually been terminated, so
            // tapping it cold-launched an app that never turned the mic on.
            // `task` runs once per launch and closes that hole;
            // `autoStartIfPossible` is idempotent, so an overlap is harmless.
            .task { await SessionController.shared.autoStartIfPossible() }
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
