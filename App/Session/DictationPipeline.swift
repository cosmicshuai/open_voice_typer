import Foundation

/// Thrown when an ASR or polish attempt exceeds its per-attempt timeout
/// budget. Surfaced to the user only after all retries are exhausted.
struct DictationTimeout: LocalizedError {
    var errorDescription: String? {
        "The request kept timing out. Check your connection and try again."
    }
}

/// Runs one dictation through ASR and (unless the style is Raw) polish,
/// using whatever providers the current settings select.
struct DictationPipeline: Sendable {
    struct Outcome: Sendable {
        var rawText: String
        var polishedText: String
        /// Model that produced the final text ("on-device", "gpt-4o-mini", …).
        var engineName: String
        var audioSeconds: Double
    }

    var settings: ProviderSettings

    /// 16 kHz mono 16-bit WAV: 32,000 audio bytes per second after the header.
    static func audioSeconds(ofWAV wavData: Data) -> Double {
        Double(max(0, wavData.count - 44)) / 32_000
    }

    var asrEngineName: String {
        switch settings.asrBackend {
        case .apple: "on-device"
        case .openAICompatible: settings.asrModel
        }
    }

    var polishEngineName: String {
        switch settings.polishBackend {
        case .openAICompatible: settings.polishModel
        case .deepseek: settings.deepseekModel
        case .anthropic: settings.anthropicModel
        case .gemini: settings.geminiModel
        }
    }

    func run(wavData: Data, style: Style) async throws -> Outcome {
        let hotwords = SharedCatalog.loadDictionary().map(\.term)
        let seconds = Self.audioSeconds(ofWAV: wavData)

        #if DEBUG
        // UI-test hook: the simulator has no working speech stack and test
        // runs have no API keys, so E2E tests fake only the provider calls —
        // recording, the keyboard↔app bridge, and insertion all stay real.
        if let fake = ProcessInfo.processInfo.environment["OVT_FAKE_PIPELINE"] {
            try? await Task.sleep(for: .milliseconds(300))
            return Outcome(rawText: fake, polishedText: fake, engineName: "uitest-fake", audioSeconds: seconds)
        }
        #endif

        // ASR and polish are separate network hops, so each gets its own
        // timeout-and-retry budget: a slow/hung request is abandoned and
        // retried rather than stalling the whole dictation.
        let asr = makeASRProvider()
        let raw = try await Self.withTimeoutRetry {
            try await asr.transcribe(ASRRequest(
                wavData: wavData,
                language: settings.asrLanguage,
                hotwords: hotwords
            ))
        }

        guard style.id != Style.raw.id else {
            return Outcome(rawText: raw, polishedText: raw, engineName: asrEngineName, audioSeconds: seconds)
        }

        let polished = try await polishOnly(rawText: raw, style: style)
        return Outcome(rawText: raw, polishedText: polished, engineName: polishEngineName, audioSeconds: seconds)
    }

    /// Reruns just the polish stage — used by History's Re-polish and the
    /// template editor's preview.
    func polishOnly(rawText: String, style: Style) async throws -> String {
        guard style.id != Style.raw.id else { return rawText }
        let polisher = makePolishProvider()
        let request = PolishRequest(
            transcript: rawText,
            style: style,
            dictionary: SharedCatalog.loadDictionary().map(\.term),
            targetLanguage: settings.targetLanguage
        )
        return try await Self.withTimeoutRetry {
            try await polisher.polish(request)
        }
    }

    // MARK: Timeout + retry

    /// Attempts an operation up to `maxAttempts` times, giving each attempt
    /// `timeout` to finish. A timed-out (or connection-lost) attempt is
    /// retried with a short backoff; any other error fails immediately (a bad
    /// key or malformed request won't fix itself). Matches the requirement to
    /// retry ASR and polish three times on timeout.
    static let maxAttempts = 3
    static let attemptTimeout: Duration = .seconds(20)

    static func withTimeoutRetry<T: Sendable>(
        maxAttempts: Int = DictationPipeline.maxAttempts,
        timeout: Duration = DictationPipeline.attemptTimeout,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await withTimeout(timeout, operation)
            } catch {
                lastError = error
                guard Self.isRetryable(error), attempt < maxAttempts else { throw error }
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
        throw lastError ?? DictationTimeout()
    }

    /// Races `operation` against a timeout; whichever finishes first wins and
    /// the other is cancelled.
    private static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw DictationTimeout()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if error is DictationTimeout { return true }
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]
                .contains(urlError.code)
        }
        return false
    }

    private func makeASRProvider() -> ASRProvider {
        switch settings.asrBackend {
        case .apple:
            AppleSpeechASR(language: settings.asrLanguage)
        case .openAICompatible:
            OpenAICompatibleASR(
                baseURL: settings.asrBaseURL,
                model: settings.asrModel,
                apiKey: { KeychainStore.get(.asrAPIKey) }
            )
        }
    }

    private func makePolishProvider() -> PolishProvider {
        switch settings.polishBackend {
        case .openAICompatible:
            OpenAICompatibleLLM(
                baseURL: settings.polishBaseURL,
                model: settings.polishModel,
                apiKey: { KeychainStore.get(.polishOpenAIKey) }
            )
        case .deepseek:
            OpenAICompatibleLLM(
                baseURL: ProviderSettings.deepseekBaseURL,
                model: settings.deepseekModel,
                apiKey: { KeychainStore.get(.polishDeepSeekKey) }
            )
        case .anthropic:
            AnthropicLLM(
                model: settings.anthropicModel,
                apiKey: { KeychainStore.get(.polishAnthropicKey) }
            )
        case .gemini:
            GeminiLLM(
                model: settings.geminiModel,
                apiKey: { KeychainStore.get(.polishGeminiKey) }
            )
        }
    }
}
