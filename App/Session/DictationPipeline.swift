import Foundation

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

        let raw = try await makeASRProvider().transcribe(ASRRequest(
            wavData: wavData,
            language: settings.asrLanguage,
            hotwords: hotwords
        ))

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
        return try await makePolishProvider().polish(PolishRequest(
            transcript: rawText,
            style: style,
            dictionary: SharedCatalog.loadDictionary().map(\.term),
            targetLanguage: settings.targetLanguage
        ))
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
