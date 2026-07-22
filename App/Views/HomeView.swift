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
            VStack(spacing: 20) {
                stylePicker
                Spacer()
                recordButton
                Text(model.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                resultSection
                keyboardFooter
            }
            .padding()
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

    private var stylePicker: some View {
        Picker("Template", selection: $model.selectedStyleID) {
            ForEach(model.styles) { style in
                Text(style.name).tag(style.id)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.isBusy)
    }

    private var recordButton: some View {
        Button(action: { model.toggleRecording() }) {
            ZStack {
                Circle()
                    .fill(model.isRecording ? Color.red : Color.appAccent)
                    .frame(width: 96, height: 96)
                    .scaleEffect(1 + CGFloat(model.audioLevel) * 0.35)
                    .animation(.easeOut(duration: 0.1), value: model.audioLevel)
                Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isTranscribing)
        .accessibilityLabel(model.isRecording ? "Stop recording" : "Start recording")
    }

    @ViewBuilder
    private var resultSection: some View {
        if !model.polishedText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Result").font(.headline)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = model.polishedText
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .font(.subheadline)
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
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
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

@MainActor
@Observable
final class HomeViewModel {
    var styles: [Style] = SharedCatalog.loadStyles()
    var selectedStyleID: String = SettingsStore.load().selectedStyleID {
        didSet {
            var settings = SettingsStore.load()
            settings.selectedStyleID = selectedStyleID
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
