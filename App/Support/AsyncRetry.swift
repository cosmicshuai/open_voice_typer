import Foundation

/// Thrown when an operation exceeds the time budget given to it by
/// `AsyncRetry`. Surfaced to the user only after all retries are exhausted.
struct TimeoutError: LocalizedError {
    var errorDescription: String? {
        "The request kept timing out. Check your connection and try again."
    }
}

/// Generic timeout + retry for async work. Not specific to dictation — any
/// network-ish call can adopt it, which keeps the retry policy in one place
/// instead of copied into each provider or pipeline.
enum AsyncRetry {
    static let defaultMaxAttempts = 3
    static let defaultTimeout: Duration = .seconds(20)

    /// Attempts `operation` up to `maxAttempts` times, giving each attempt
    /// `timeout` to finish. A timed-out or connection-dropped attempt is
    /// retried after a short backoff; every other error propagates
    /// immediately (a bad key or malformed request won't fix itself).
    static func retryingOnTimeout<T: Sendable>(
        maxAttempts: Int = defaultMaxAttempts,
        timeout: Duration = defaultTimeout,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await withTimeout(timeout, operation)
            } catch {
                lastError = error
                guard isRetryable(error), attempt < maxAttempts else { throw error }
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
        throw lastError ?? TimeoutError()
    }

    /// Races `operation` against a timeout; whichever finishes first wins and
    /// the loser is cancelled.
    static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimeoutError()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// Timeouts and transient connection failures are worth another try; a
    /// bad key or malformed request is not.
    static func isRetryable(_ error: Error) -> Bool {
        if error is TimeoutError { return true }
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]
                .contains(urlError.code)
        }
        return false
    }
}
