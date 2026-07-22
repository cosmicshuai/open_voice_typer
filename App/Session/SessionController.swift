import AVFoundation
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

    /// UI-facing mic level for the in-app dictation button (the bridge gets
    /// its levels separately, only during keyboard-initiated captures).
    var onUILevel: ((Float) -> Void)?

    private var heartbeatTimer: Timer?
    private var autoEndTimer: Timer?
    private var commandToken: DarwinNotifier.ObservationToken?
    private var interruptionObserver: (any NSObjectProtocol)?
    private var activeCommand: KeyboardCommand?
    private var lastLevelPublish: Date = .distantPast
    /// Ids already executed — the command queue is append-only (the keyboard
    /// owns the slot), so replay protection lives here, not in clearing.
    private var handledCommandIDs: [UUID] = []
    /// Commands older than this are leftovers from a dead keyboard/app
    /// lifetime and must not fire a surprise recording.
    private static let commandMaxAge: TimeInterval = 20

    private init() {
        modelContainer = try! ModelContainer(for: TranscriptRecord.self)
        recorder.onLevel = { [weak self] level in
            MainActor.assumeIsolated {
                self?.publishLevel(level)
                self?.onUILevel?(level)
            }
        }
    }

    // MARK: Session lifecycle

    /// Starts a session without user interaction when possible. Called on
    /// app foreground so opening the app is all the setup a dictation needs
    /// (Typeless-style); never prompts for permission — the first manual
    /// Start does that. Also repairs an already-active session whose engine
    /// died while backgrounded (an interruption that couldn't be recovered
    /// until the app came forward), so reopening the app always fixes things.
    func autoStartIfPossible() async {
        guard AVAudioApplication.shared.recordPermission == .granted else { return }
        if isActive {
            if !recorder.isEngineHealthy { try? recorder.recoverEngine() }
            return
        }
        await start()
    }

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
            Task { @MainActor in SessionController.shared.handlePendingCommands() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { note in
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init) == .ended
            Task { @MainActor in
                if ended { try? SessionController.shared.recorder.recoverEngine() }
            }
        }

        beat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in SessionController.shared.beat() }
        }

        scheduleAutoEnd()

        DictationBridge.publish(PipelineState(phase: .idle))
        // Catch a command the keyboard may have queued while we were starting.
        handlePendingCommands()
    }

    /// (Re)arms the idle auto-end timer. Called on start and on every
    /// dictation so the window measures inactivity, not session age — an
    /// actively used session never expires mid-use. 0 minutes means never.
    private func scheduleAutoEnd() {
        autoEndTimer?.invalidate()
        autoEndTimer = nil
        let minutes = SettingsStore.load().sessionAutoEndMinutes
        guard minutes > 0 else { return }
        autoEndTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(minutes * 60),
            repeats: false
        ) { _ in
            Task { @MainActor in SessionController.shared.stop() }
        }
    }

    func stop() {
        guard isActive else { return }
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        autoEndTimer?.invalidate()
        autoEndTimer = nil
        commandToken = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        recorder.stopEngine()
        isActive = false
        startedAt = nil
        activeCommand = nil
        DictationBridge.publish(nil as SessionHeartbeat?)
        DictationBridge.publish(PipelineState(phase: .idle))
    }

    /// The heartbeat doubles as an engine watchdog. If the engine was
    /// interrupted (a call, Siri, another audio app, the screen locking) it
    /// tries to bring it back — but NEVER tears the session down for a
    /// transient failure, or the user would have to reopen the app after every
    /// blip. While the engine is unhealthy it simply withholds the heartbeat,
    /// so the keyboard shows "open the app" for the outage and resumes on its
    /// own once recovery succeeds (or the app is foregrounded).
    private func beat() {
        guard startedAt != nil else { return }
        if !recorder.isEngineHealthy {
            try? recorder.recoverEngine()
            guard recorder.isEngineHealthy else { return }
        }
        DictationBridge.publish(SessionHeartbeat(startedAt: startedAt ?? .now, lastBeatAt: .now))
    }

    // MARK: Command handling

    private func handlePendingCommands() {
        guard isActive else { return }
        for command in DictationBridge.commandQueue() {
            guard !handledCommandIDs.contains(command.id) else { continue }
            handledCommandIDs.append(command.id)
            if handledCommandIDs.count > 64 { handledCommandIDs.removeFirst(32) }
            guard Date.now.timeIntervalSince(command.issuedAt) < Self.commandMaxAge else { continue }
            execute(command)
        }
    }

    private func execute(_ command: KeyboardCommand) {
        // Any dictation activity resets the idle auto-end window.
        scheduleAutoEnd()
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
