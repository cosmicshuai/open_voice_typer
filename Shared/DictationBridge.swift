import Foundation

/// Typed mailbox between the keyboard extension and the main app, backed by
/// App Group `UserDefaults`. Each slot is last-writer-wins JSON; Darwin
/// notifications (`DarwinNotifier`) tell the other side when a slot changed.
///
/// Requires the keyboard to have Full Access (App Group reads are blocked
/// without it) — `isAvailable` is how callers detect that.
enum DictationBridge {
    private enum Key {
        static let commands = "bridge.commands"
        static let state = "bridge.state"
        static let result = "bridge.result"
        static let heartbeat = "bridge.sessionHeartbeat"
    }

    /// False when the App Group container can't be opened (e.g. the keyboard
    /// is running without Full Access).
    static var isAvailable: Bool {
        AppGroup.defaults != nil
    }

    // MARK: Keyboard -> App

    /// Commands are an append-only queue (only the keyboard writes it) so a
    /// quick start→stop can never overwrite itself the way a single slot
    /// could. The app dedupes by command id instead of clearing the slot —
    /// clearing from the reader side would race the keyboard's appends.
    static func send(_ command: KeyboardCommand) {
        let queue = (commandQueue() + [command]).suffix(8)
        write(Array(queue), key: Key.commands)
        DarwinNotifier.post(.commandPosted)
    }

    static func commandQueue() -> [KeyboardCommand] {
        read([KeyboardCommand].self, key: Key.commands) ?? []
    }

    /// Test/setup helper; production readers dedupe rather than clear.
    static func clearCommands() {
        AppGroup.defaults?.removeObject(forKey: Key.commands)
    }

    // MARK: App -> Keyboard

    static func publish(_ state: PipelineState) {
        write(state, key: Key.state)
        DarwinNotifier.post(.statePosted)
    }

    static func currentState() -> PipelineState? {
        read(PipelineState.self, key: Key.state)
    }

    static func publish(_ result: DictationResult) {
        write(result, key: Key.result)
        DarwinNotifier.post(.resultPosted)
    }

    static func latestResult() -> DictationResult? {
        read(DictationResult.self, key: Key.result)
    }

    /// The keyboard clears a result once inserted so it is never replayed.
    /// It is a single shared slot, so a keyboard opening in a *different* app
    /// must discard any result it did not itself request (see
    /// `VoicePanelModel.activate`) — otherwise app A's transcript could land
    /// in app B's text field.
    static func clearResult() {
        AppGroup.defaults?.removeObject(forKey: Key.result)
    }

    // MARK: Session heartbeat

    static func publish(_ heartbeat: SessionHeartbeat?) {
        if let heartbeat {
            write(heartbeat, key: Key.heartbeat)
        } else {
            AppGroup.defaults?.removeObject(forKey: Key.heartbeat)
        }
        DarwinNotifier.post(.sessionChanged)
    }

    static func sessionHeartbeat() -> SessionHeartbeat? {
        read(SessionHeartbeat.self, key: Key.heartbeat)
    }

    static var isSessionAlive: Bool {
        sessionHeartbeat()?.isAlive ?? false
    }

    // MARK: Plumbing

    private static func write(_ value: some Encodable, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        AppGroup.defaults?.set(data, forKey: key)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = AppGroup.defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
