import SwiftUI

/// In-app dictation: record, transcribe, polish, copy. There is no
/// user-facing "session" — opening the app keeps the microphone ready in
/// the background (that's what powers the keyboard in other apps), and the
/// mic button here rides the same engine.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = HomeViewModel()
    @State private var session = SessionController.shared

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundWash
                VStack(spacing: 20) {
                    styleChips
                    Spacer()
                    recordButton
                    Text(model.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .animation(.default, value: model.statusText)
                    Spacer()
                    resultSection
                    keyboardFooter
                }
                .padding()
            }
            .navigationTitle("Open Voice Typer")
            .onAppear {
                model.onCompleted = { record in modelContext.insert(record) }
            }
            .alert("Dictation failed", isPresented: $model.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage)
            }
        }
    }

    /// A quiet accent-tinted wash from the top so the screen has depth
    /// without competing with content. Adapts to both appearances.
    private var backgroundWash: some View {
        LinearGradient(
            colors: [Color.appAccent.opacity(0.12), .clear],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    /// Template picker as scrollable capsule chips — same design language as
    /// History's filters, and it doesn't cramp when custom templates exist.
    private var styleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.styles) { style in
                    let isOn = style.id == model.selectedStyleID
                    Button {
                        model.selectedStyleID = style.id
                    } label: {
                        Text(style.name)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isOn ? AnyShapeStyle(LinearGradient.appAccentFill) : AnyShapeStyle(.quaternary),
                                in: Capsule()
                            )
                            .foregroundStyle(isOn ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.5 : 1)
    }

    private var recordButton: some View {
        Button(action: { model.toggleRecording() }) {
            ZStack {
                if model.isRecording {
                    PulseRing(delay: 0)
                    PulseRing(delay: 0.7)
                }
                Circle()
                    .fill(model.isRecording ? LinearGradient.recordingFill : .appAccentFill)
                    .frame(width: 104, height: 104)
                    .scaleEffect(1 + CGFloat(model.audioLevel) * 0.35)
                    .animation(.easeOut(duration: 0.1), value: model.audioLevel)
                    .shadow(
                        color: (model.isRecording ? Color.red : Color.appAccent).opacity(0.35),
                        radius: 18, y: 8
                    )
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 180, height: 180)
            .animation(.spring(duration: 0.35), value: model.isRecording)
        }
        .buttonStyle(.plain)
        .disabled(model.isTranscribing)
        .accessibilityLabel(model.isRecording ? "Stop recording" : "Start recording")
    }

    @ViewBuilder
    private var resultSection: some View {
        if !model.polishedText.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Result").font(.headline)
                    Spacer()
                    CopyButton(text: model.polishedText)
                }
                ScrollView {
                    Text(model.polishedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)

                if model.rawText != model.polishedText {
                    DisclosureGroup("Raw transcript") {
                        Text(model.rawText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// One quiet line about the keyboard, in place of the old session card.
    private var keyboardFooter: some View {
        Group {
            if let error = session.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if session.isActive {
                Label("Voice keyboard ready — dictate in any app.", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
            } else {
                Label("Microphone is off — it turns on whenever this app opens.", systemImage: "mic.slash")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
    }
}

/// Expanding ring that radiates from the mic button while recording.
private struct PulseRing: View {
    let delay: Double
    @State private var animating = false

    var body: some View {
        Circle()
            .stroke(Color.red.opacity(0.4), lineWidth: 2)
            .frame(width: 104, height: 104)
            .scaleEffect(animating ? 1.65 : 1)
            .opacity(animating ? 0 : 0.8)
            .animation(
                .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(delay),
                value: animating
            )
            .onAppear { animating = true }
    }
}

/// Copy with a moment of visible confirmation.
private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            withAnimation { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { copied = false }
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(copied ? .green : Color.appAccent)
    }
}

@MainActor
@Observable
final class HomeViewModel {
    var styles: [Style] = SharedCatalog.loadStyles()
    var selectedStyleID: String = SettingsStore.load().selectedStyleID {
        didSet {
            var settings = SettingsStore.load()
            settings.selectedStyleID = selectedStyleID
            if selectedStyleID != Style.translate.id {
                settings.lastDictateStyleID = selectedStyleID
            }
            SettingsStore.save(settings)
        }
    }

    var isRecording = false
    var isTranscribing = false
    var audioLevel: Float = 0
    var rawText = ""
    var polishedText = ""
    var showError = false
    var errorMessage = ""
    var onCompleted: ((TranscriptRecord) -> Void)?

    var isBusy: Bool { isRecording || isTranscribing }

    var statusText: String {
        if isRecording { return "Listening… tap to finish" }
        if isTranscribing { return "Transcribing & polishing…" }
        return "Tap to dictate"
    }

    private let session = SessionController.shared

    init() {
        session.onUILevel = { [weak self] level in
            guard let self else { return }
            audioLevel = isRecording ? level : 0
        }
    }

    func toggleRecording() {
        isRecording ? finishRecording() : startRecording()
    }

    private func startRecording() {
        Task {
            // In-app dictation shares the background engine that serves the
            // keyboard; first ever tap prompts for mic permission via start().
            if !session.isActive {
                await session.start()
            }
            guard session.isActive else {
                errorMessage = session.lastError
                    ?? AudioRecorderError.microphonePermissionDenied.localizedDescription
                showError = true
                return
            }
            session.recorder.beginCapture()
            isRecording = true
            rawText = ""
            polishedText = ""
        }
    }

    private func finishRecording() {
        // The engine keeps running for the keyboard; only the capture ends.
        let wav = session.recorder.endCapture()
        isRecording = false
        isTranscribing = true

        let settings = SettingsStore.load()
        let style = SharedCatalog.style(id: selectedStyleID) ?? .light
        Task {
            defer { isTranscribing = false }
            do {
                let outcome = try await DictationPipeline(settings: settings).run(wavData: wav, style: style)
                rawText = outcome.rawText
                polishedText = outcome.polishedText
                onCompleted?(TranscriptRecord(
                    rawText: outcome.rawText,
                    polishedText: outcome.polishedText,
                    styleID: style.id,
                    source: .app,
                    engineName: outcome.engineName,
                    audioSeconds: outcome.audioSeconds
                ))
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    HomeView()
}
