import Foundation

/// Runs one dictation through ASR and (unless the style is Raw) polish,
/// using whatever providers the current settings select.
struct DictationPipeline: Sendable {
    struct Outcome: Sendable {
        var rawText: String
        var polishedText: String
    }

    var settings: ProviderSettings

    func run(wavData: Data, style: Style) async throws -> Outcome {
        let hotwords = SharedCatalog.loadDictionary().map(\.term)

        let raw = try await makeASRProvider().transcribe(ASRRequest(
            wavData: wavData,
            language: settings.asrLanguage,
            hotwords: hotwords
        ))

        guard style.id != Style.raw.id else {
            return Outcome(rawText: raw, polishedText: raw)
        }

        let polished = try await makePolishProvider().polish(PolishRequest(
            transcript: raw,
            style: style,
            dictionary: hotwords,
            targetLanguage: settings.targetLanguage
        ))
        return Outcome(rawText: raw, polishedText: polished)
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
