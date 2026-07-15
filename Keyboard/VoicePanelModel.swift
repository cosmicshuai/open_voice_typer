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

    /// The start-command id of the dictation we're waiting on.
    private var awaitingCommandID: UUID?
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
        default: "Tap to dictate"
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
        refreshSessionState()
    }

    func deactivate() {
        // A dictation in flight when the keyboard closes is abandoned; tell
        // the app to stop capturing.
        if phase == .recording {
            DictationBridge.send(KeyboardCommand(kind: .cancelDictation, styleID: selectedStyleID))
        }
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
            DictationBridge.send(command)
            phase = .recording
            audioLevel = 0
        case .recording:
            DictationBridge.send(KeyboardCommand(kind: .stopDictation, styleID: selectedStyleID))
            phase = .processing
        default:
            break
        }
    }

    private func consumeResult() {
        guard let result = DictationBridge.latestResult(),
              result.commandID == awaitingCommandID
        else { return }
        DictationBridge.clearResult()
        awaitingCommandID = nil

        if let message = result.errorMessage {
            phase = .error(message)
            return
        }
        insert(result.polishedText)
    }

    private func consumeState() {
        guard let state = DictationBridge.currentState() else { return }
        if phase == .recording, state.phase == .recording, state.commandID == awaitingCommandID {
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
