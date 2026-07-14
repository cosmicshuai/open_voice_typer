import Foundation

/// Typed mailbox between the keyboard extension and the main app, backed by
/// App Group `UserDefaults`. Each slot is last-writer-wins JSON; Darwin
/// notifications (`DarwinNotifier`) tell the other side when a slot changed.
///
/// Requires the keyboard to have Full Access (App Group reads are blocked
/// without it) — `isAvailable` is how callers detect that.
enum DictationBridge {
    private enum Key {
        static let command = "bridge.command"
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

    static func send(_ command: KeyboardCommand) {
        write(command, key: Key.command)
        DarwinNotifier.post(.commandPosted)
    }

    static func pendingCommand() -> KeyboardCommand? {
        read(KeyboardCommand.self, key: Key.command)
    }

    /// The app clears a command once handled so it is never replayed.
    static func clearCommand() {
        AppGroup.defaults?.removeObject(forKey: Key.command)
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
