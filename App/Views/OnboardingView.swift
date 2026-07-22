import AVFoundation
import SwiftUI

/// First-launch flow: welcome → enable keyboard → microphone/session model →
/// engine choice. Front-loads the two things the product can't work without
/// and makes "no API key yet" a non-blocker by defaulting to on-device speech.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page = 0
    @State private var cloudSelected = false

    var body: some View {
        TabView(selection: $page) {
            welcomePage.tag(0)
            keyboardPage.tag(1)
            microphonePage.tag(2)
            enginePage.tag(3)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background {
            ZStack {
                Color(.systemGroupedBackground)
                LinearGradient(
                    colors: [Color.appAccent.opacity(0.14), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
        }
        .interactiveDismissDisabled()
    }

    // MARK: Pages

    private var welcomePage: some View {
        OnboardingPage(
            primaryLabel: "Get started",
            primaryAction: { advance() }
        ) {
            WaveformGlyph()
                .padding(.top, 40)
            Text("Speak. It types.")
                .font(.largeTitle.bold())
            Text("Dictate into any app and get clean, polished text — using your own AI keys, stored only on this device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
    }

    private var keyboardPage: some View {
        OnboardingPage(
            primaryLabel: "Open Settings",
            primaryAction: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                advance()
            },
            secondaryLabel: "I'll do this later",
            secondaryAction: { advance() }
        ) {
            Text("Add the keyboard")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 14) {
                numberedStep(1, text: "Open **Settings**")
                numberedStep(2, text: "General → Keyboard → **Keyboards**")
                numberedStep(3, text: "Add New Keyboard → **Voice Typer**")
                numberedStep(4, text: "Turn on **Allow Full Access**")
            }
            .padding(.horizontal, 8)
            infoCard("Full Access lets the keyboard talk to this app. Your API keys stay in the Keychain — the keyboard can never read them.")
        }
    }

    private var microphonePage: some View {
        OnboardingPage(
            primaryLabel: "Allow microphone",
            primaryAction: {
                Task {
                    _ = await AudioRecorder.requestPermission()
                    advance()
                }
            }
        ) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(LinearGradient.appAccentFill, in: Circle())
                .shadow(color: Color.appAccent.opacity(0.35), radius: 16, y: 6)
                .padding(.top, 28)
            Text("Recording happens here")
                .font(.title.bold())
            Text("iOS doesn't let keyboards use the microphone — so this app records for it. Just open the app once, then dictate anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            infoCard("While the mic stays ready you'll see the orange indicator. It switches off after 15 minutes (adjustable in Settings); opening the app turns it back on.")
        }
    }

    private var enginePage: some View {
        OnboardingPage(
            primaryLabel: "Start dictating",
            primaryAction: { finish() }
        ) {
            Text("Pick your engine")
                .font(.title.bold())
                .padding(.top, 16)
            engineOption(
                title: "On-device",
                detail: "Free · works offline · no account or key. Uses Apple speech recognition.",
                selected: !cloudSelected
            ) { cloudSelected = false }
            engineOption(
                title: "Cloud — bring your key",
                detail: "OpenAI, Groq, Anthropic, Gemini. Higher accuracy and AI polish. Add keys any time in Settings.",
                selected: cloudSelected
            ) { cloudSelected = true }
        }
    }

    // MARK: Pieces

    private func numberedStep(_ number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color(.tertiarySystemFill), in: Circle())
            Text(.init(text))
        }
    }

    private func infoCard(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.appAccent)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 8)
    }

    private func engineOption(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appAccent)
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.appAccent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func advance() {
        withAnimation { page = min(page + 1, 3) }
    }

    private func finish() {
        var settings = SettingsStore.load()
        settings.asrBackend = cloudSelected ? .openAICompatible : .apple
        SettingsStore.save(settings)
        isPresented = false
    }
}

/// Shared page chrome: centered content column + pinned primary button.
private struct OnboardingPage<Content: View>: View {
    var primaryLabel: String
    var primaryAction: () -> Void
    var secondaryLabel: String?
    var secondaryAction: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            Button(action: primaryAction) {
                Text(primaryLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            if let secondaryLabel, let secondaryAction {
                Button(secondaryLabel, action: secondaryAction)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 56)
        .frame(maxWidth: 500)
    }
}

/// Animated equalizer bars — the app's welcome mark.
private struct WaveformGlyph: View {
    @State private var animating = false
    private let heights: [CGFloat] = [26, 44, 62, 38, 20]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(heights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(LinearGradient.appAccentFill)
                    .frame(width: 7, height: heights[index])
                    .scaleEffect(y: animating ? 1 : 0.55, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(height: 64, alignment: .bottom)
        .onAppear { animating = true }
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
