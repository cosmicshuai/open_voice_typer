import Foundation
import SwiftData
import UIKit

/// Runs a keyboard dictation session: keeps the audio engine (and therefore
/// the backgrounded app) alive, heartbeats liveness to the keyboard, executes
/// keyboard commands off the bridge, and publishes pipeline states/results.
@MainActor
@Observable
final class SessionController {
    static let shared = SessionController()

    /// SwiftData container shared with the UI (history inserts land here).
    let modelContainer: ModelContainer

    private(set) var isActive = false
    private(set) var startedAt: Date?
    var lastError: String?

    let recorder = AudioRecorder()

    private var heartbeatTimer: Timer?
    private var autoEndTimer: Timer?
    private var commandToken: DarwinNotifier.ObservationToken?
    private var activeCommand: KeyboardCommand?
    private var lastLevelPublish: Date = .distantPast

    private init() {
        modelContainer = try! ModelContainer(for: TranscriptRecord.self)
        recorder.onLevel = { [weak self] level in
            MainActor.assumeIsolated { self?.publishLevel(level) }
        }
    }

    // MARK: Session lifecycle

    func start() async {
        guard !isActive else { return }
        guard await AudioRecorder.requestPermission() else {
            lastError = AudioRecorderError.microphonePermissionDenied.localizedDescription
            return
        }
        do {
            try recorder.startEngine()
        } catch {
            lastError = error.localizedDescription
            return
        }

        isActive = true
        startedAt = .now
        lastError = nil

        commandToken = DarwinNotifier.observe(.commandPosted) {
            Task { @MainActor in SessionController.shared.handlePendingCommand() }
        }

        beat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in SessionController.shared.beat() }
        }

        let autoEndMinutes = SettingsStore.load().sessionAutoEndMinutes
        if autoEndMinutes > 0 {
            autoEndTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(autoEndMinutes * 60),
                repeats: false
            ) { _ in
                Task { @MainActor in SessionController.shared.stop() }
            }
        }

        DictationBridge.publish(PipelineState(phase: .idle))
        // Catch a command the keyboard may have queued while we were starting.
        handlePendingCommand()
    }

    func stop() {
        guard isActive else { return }
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        autoEndTimer?.invalidate()
        autoEndTimer = nil
        commandToken = nil
        recorder.stopEngine()
        isActive = false
        startedAt = nil
        activeCommand = nil
        DictationBridge.publish(nil as SessionHeartbeat?)
        DictationBridge.publish(PipelineState(phase: .idle))
    }

    private func beat() {
        guard let startedAt else { return }
        DictationBridge.publish(SessionHeartbeat(startedAt: startedAt, lastBeatAt: .now))
    }

    // MARK: Command handling

    private func handlePendingCommand() {
        guard isActive, let command = DictationBridge.pendingCommand() else { return }
        DictationBridge.clearCommand()

        switch command.kind {
        case .startDictation:
            guard activeCommand == nil else { return }
            activeCommand = command
            recorder.beginCapture()
            DictationBridge.publish(PipelineState(phase: .recording, commandID: command.id))

        case .stopDictation:
            // Results are attributed to the START command's id; the keyboard
            // remembers that id and matches it when the result arrives.
            guard let active = activeCommand else { return }
            activeCommand = nil
            let wav = recorder.endCapture()
            DictationBridge.publish(PipelineState(phase: .transcribing, commandID: active.id))
            runPipeline(command: active, wavData: wav)

        case .cancelDictation:
            activeCommand = nil
            recorder.cancelCapture()
            DictationBridge.publish(PipelineState(phase: .idle))
        }
    }

    private func runPipeline(command: KeyboardCommand, wavData: Data) {
        let settings = SettingsStore.load()
        let style = SharedCatalog.style(id: command.styleID) ?? .light

        Task {
            do {
                let outcome = try await DictationPipeline(settings: settings)
                    .run(wavData: wavData, style: style)
                DictationBridge.publish(DictationResult(
                    commandID: command.id,
                    styleID: style.id,
                    rawText: outcome.rawText,
                    polishedText: outcome.polishedText
                ))
                saveHistory(outcome: outcome, styleID: style.id)
            } catch {
                DictationBridge.publish(DictationResult(
                    commandID: command.id,
                    styleID: style.id,
                    rawText: "",
                    polishedText: "",
                    errorMessage: error.localizedDescription
                ))
            }
            DictationBridge.publish(PipelineState(phase: .idle))
        }
    }

    private func saveHistory(outcome: DictationPipeline.Outcome, styleID: String) {
        modelContainer.mainContext.insert(TranscriptRecord(
            rawText: outcome.rawText,
            polishedText: outcome.polishedText,
            styleID: styleID,
            source: .keyboard,
            engineName: outcome.engineName,
            audioSeconds: outcome.audioSeconds
        ))
    }

    // MARK: Level metering

    private func publishLevel(_ level: Float) {
        guard isActive, activeCommand != nil else { return }
        // Throttle bridge writes; the keyboard animates between updates.
        let now = Date.now
        guard now.timeIntervalSince(lastLevelPublish) > 0.15 else { return }
        lastLevelPublish = now
        DictationBridge.publish(PipelineState(
            phase: .recording,
            commandID: activeCommand?.id,
            audioLevel: level
        ))
    }
}
