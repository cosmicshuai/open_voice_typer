import Foundation
import SwiftUI

/// Keyboard-side state machine. Talks to the main app exclusively through
/// `DictationBridge`; performs text insertion through closures wired to the
/// `UIInputViewController`'s text document proxy.
@MainActor
@Observable
final class VoicePanelModel {
    enum Phase: Equatable {
        case noFullAccess
        case noSession
        case idle
        case recording
        case processing
        case error(String)

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    /// The app must acknowledge a start command (by publishing a recording
    /// state) within this window, or the tap is declared failed instead of
    /// letting the user talk into a dead mic.
    static let startAckTimeout: TimeInterval = 3
    /// Ceiling for ASR + polish; beyond it the keyboard stops waiting.
    static let resultTimeout: TimeInterval = 60
    /// A tap-start-to-stop shorter than this is treated as a misclick and
    /// discarded locally — no round trip to the app, nothing to wait for.
    static let minRecordingSeconds: TimeInterval = 0.6

    var phase: Phase = .idle
    var audioLevel: Float = 0
    var styles: [Style] = []
    var selectedStyleID: String = Style.light.id {
        didSet {
            var settings = SettingsStore.load()
            settings.selectedStyleID = selectedStyleID
            SettingsStore.save(settings)
        }
    }

    let needsInputModeSwitchKey: Bool
    var onGlobe: () -> Void = {}
    var insertTextHandler: (String) -> Void = { _ in }
    var deleteBackwardHandler: () -> Void = {}

    /// The start-command id of the dictation we're waiting on. Mirrored into
    /// the bridge so a result that lands while the keyboard is dismissed is
    /// inserted when it reappears instead of being lost.
    private var awaitingCommandID: UUID? {
        didSet { DictationBridge.setAwaitingCommandID(awaitingCommandID) }
    }
    private var startAcknowledged = false
    private var recordingStartedAt: Date?
    private var timeoutTask: Task<Void, Never>?
    private var lastInsertedText = ""
    private var tokens: [DarwinNotifier.ObservationToken] = []
    private var pollTimer: Timer?

    init(needsInputModeSwitchKey: Bool) {
        self.needsInputModeSwitchKey = needsInputModeSwitchKey
    }

    var canDictate: Bool {
        switch phase {
        case .idle, .error: true
        default: false
        }
    }

    var canUndo: Bool {
        !lastInsertedText.isEmpty && phase != .recording && phase != .processing
    }

    var selectedStyleName: String {
        styles.first { $0.id == selectedStyleID }?.name ?? "Style"
    }

    var statusText: String {
        switch phase {
        case .recording: "Listening… tap to finish"
        case .processing: "Working…"
        case .error(let message): message
        default: "Tap to speak"
        }
    }

    // MARK: Lifecycle (wired from KeyboardViewController)

    func activate() {
        guard DictationBridge.isAvailable else {
            phase = .noFullAccess
            return
        }
        styles = SharedCatalog.loadStyles()
        selectedStyleID = SettingsStore.load().selectedStyleID

        tokens = [
            DarwinNotifier.observe(.resultPosted) { [weak self] in
                Task { @MainActor in self?.consumeResult() }
            },
            DarwinNotifier.observe(.statePosted) { [weak self] in
                Task { @MainActor in self?.consumeState() }
            },
            DarwinNotifier.observe(.sessionChanged) { [weak self] in
                Task { @MainActor in self?.refreshSessionState() }
            },
        ]
        // Darwin delivery to extensions is reliable in the foreground, but a
        // slow poll catches anything missed (e.g. a heartbeat going stale).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSessionState()
                self?.consumeResult()
            }
        }

        // Resume a dictation that was still processing when the keyboard was
        // last dismissed — its result may already be waiting, or still coming.
        if let pending = DictationBridge.awaitingCommandID() {
            awaitingCommandID = pending
            phase = .processing
            scheduleTimeout(after: Self.resultTimeout, ifStillAwaiting: pending) { [weak self] in
                self?.fail("Timed out waiting for the result. Try again.")
            }
        }

        // Consume any waiting result BEFORE the liveness check — the session
        // may have ended right after publishing it, and the text still counts.
        consumeResult()
        refreshSessionState()
    }

    func deactivate() {
        // A recording in flight when the keyboard closes is abandoned; tell
        // the app to stop capturing. A *processing* dictation stays awaited
        // (persisted) and is picked up on the next activate.
        if phase == .recording {
            DictationBridge.send(KeyboardCommand(kind: .cancelDictation, styleID: selectedStyleID))
            awaitingCommandID = nil
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        tokens = []
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: Dictation

    func toggleDictation() {
        switch phase {
        case .idle, .error:
            let command = KeyboardCommand(kind: .startDictation, styleID: selectedStyleID)
            awaitingCommandID = command.id
            startAcknowledged = false
            recordingStartedAt = Date()
            DictationBridge.send(command)
            phase = .recording
            audioLevel = 0
            scheduleTimeout(after: Self.startAckTimeout, ifStillAwaiting: command.id) { [weak self] in
                guard let self, !self.startAcknowledged, self.phase == .recording else { return }
                DictationBridge.send(KeyboardCommand(kind: .cancelDictation, styleID: self.selectedStyleID))
                self.fail("The app didn't start recording. Open Open Voice Typer once, then try again.")
            }
        case .recording:
            // A quick tap-tap (misclick) produced too little audio to be worth
            // transcribing — cancel it locally so there's nothing to wait for.
            if let startedAt = recordingStartedAt,
               Date().timeIntervalSince(startedAt) < Self.minRecordingSeconds {
                DictationBridge.send(KeyboardCommand(kind: .cancelDictation, styleID: selectedStyleID))
                awaitingCommandID = nil
                recordingStartedAt = nil
                timeoutTask?.cancel()
                timeoutTask = nil
                phase = .error("Hold the button while you speak.")
                return
            }
            recordingStartedAt = nil
            let id = awaitingCommandID
            DictationBridge.send(KeyboardCommand(kind: .stopDictation, styleID: selectedStyleID))
            phase = .processing
            scheduleTimeout(after: Self.resultTimeout, ifStillAwaiting: id) { [weak self] in
                self?.fail("Timed out waiting for the result. Try again.")
            }
        default:
            break
        }
    }

    /// Arms the single failure timer for the dictation identified by `id`;
    /// any state advance re-arms or cancels it.
    private func scheduleTimeout(
        after seconds: TimeInterval,
        ifStillAwaiting id: UUID?,
        onTimeout: @escaping @MainActor () -> Void
    ) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self.awaitingCommandID == id, id != nil else { return }
            onTimeout()
        }
    }

    private func fail(_ message: String) {
        awaitingCommandID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        phase = .error(message)
    }

    private func consumeResult() {
        guard let result = DictationBridge.latestResult(),
              result.commandID == awaitingCommandID
        else { return }
        DictationBridge.clearResult()
        awaitingCommandID = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        if let message = result.errorMessage {
            phase = .error(message)
            return
        }
        insert(result.polishedText)
    }

    private func consumeState() {
        guard let state = DictationBridge.currentState() else { return }
        guard state.commandID == awaitingCommandID, awaitingCommandID != nil else { return }
        if phase == .recording, state.phase == .recording {
            startAcknowledged = true
            audioLevel = state.audioLevel
        }
    }

    private func refreshSessionState() {
        guard DictationBridge.isAvailable else {
            phase = .noFullAccess
            return
        }
        let alive = DictationBridge.isSessionAlive
        switch phase {
        case .noSession where alive:
            phase = .idle
        case .idle where !alive, .error where !alive:
            phase = .noSession
        case .recording where !alive, .processing where !alive:
            // The app died mid-dictation.
            awaitingCommandID = nil
            timeoutTask?.cancel()
            phase = .noSession
        default:
            break
        }
    }

    // MARK: Text operations

    func insertText(_ text: String) {
        insertTextHandler(text)
    }

    func deleteBackward() {
        deleteBackwardHandler()
    }

    /// Streams the text in character-by-character for a typing feel, capped
    /// at ~1.5 s total so long dictations don't crawl.
    private func insert(_ text: String) {
        guard !text.isEmpty else {
            phase = .idle
            return
        }
        lastInsertedText = text
        let delayMS = min(6, 1500 / text.count)
        guard delayMS >= 1 else {
            insertTextHandler(text)
            phase = .idle
            return
        }
        phase = .processing
        Task { @MainActor in
            for character in text {
                insertTextHandler(String(character))
                try? await Task.sleep(for: .milliseconds(delayMS))
            }
            phase = .idle
        }
    }

    func undoLastInsert() {
        guard !lastInsertedText.isEmpty else { return }
        for _ in 0..<lastInsertedText.count {
            deleteBackwardHandler()
        }
        lastInsertedText = ""
    }
}
