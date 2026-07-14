import SwiftUI

/// In-app dictation: record, transcribe, polish, copy. This screen makes the
/// app usable standalone before the keyboard extension lands.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = HomeViewModel()
    @State private var session = SessionController.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                sessionCard
                stylePicker
                Spacer()
                if session.isActive {
                    Label("Session running — dictate from the Voice Typer keyboard in any app.", systemImage: "keyboard.badge.ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    recordButton
                    Text(model.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                resultSection
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

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Keyboard Session", systemImage: "keyboard.badge.waveform")
                    .font(.headline)
                Spacer()
                Button(session.isActive ? "End" : "Start") {
                    if session.isActive {
                        session.stop()
                    } else {
                        Task { await session.start() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(session.isActive ? .red : .appAccent)
            }
            Text(session.isActive
                 ? "Microphone session is live. The Voice Typer keyboard can now dictate anywhere. Ending the session or force-quitting this app stops it."
                 : "Start a session to dictate from the Voice Typer keyboard in other apps. The mic indicator stays on while a session runs.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = session.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
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

    private let recorder = AudioRecorder()

    init() {
        recorder.onLevel = { [weak self] level in
            MainActor.assumeIsolated { self?.audioLevel = level }
        }
    }

    func toggleRecording() {
        isRecording ? finishRecording() : startRecording()
    }

    private func startRecording() {
        Task {
            guard await AudioRecorder.requestPermission() else {
                present(AudioRecorderError.microphonePermissionDenied)
                return
            }
            do {
                try recorder.startEngine()
                recorder.beginCapture()
                isRecording = true
                rawText = ""
                polishedText = ""
            } catch {
                present(error)
            }
        }
    }

    private func finishRecording() {
        let wav = recorder.endCapture()
        recorder.stopEngine()
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
                present(error)
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

#Preview {
    HomeView()
}
