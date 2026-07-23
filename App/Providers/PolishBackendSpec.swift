import Foundation

/// Everything the app needs to know about one polish backend, in a single
/// place. Adding a provider means adding one `PolishBackendSpec` to `all`
/// (plus its enum case + Keychain slot) — the pipeline and the settings UI
/// read from here instead of each carrying their own `switch`.
/// `@unchecked Sendable`: the only non-`Sendable`-inferred members are the
/// key paths, which are immutable value-semantics descriptors and safe to
/// share across threads.
struct PolishBackendSpec: @unchecked Sendable {
    let backend: ProviderSettings.PolishBackend
    /// Keychain slot holding this backend's API key.
    let keychainKey: KeychainStore.Key
    /// Settings field holding this backend's model name.
    let modelKeyPath: WritableKeyPath<ProviderSettings, String>
    /// Settings field for the base URL, or nil for a fixed endpoint.
    let baseURLKeyPath: WritableKeyPath<ProviderSettings, String>?
    /// Fixed model choices offered as a quick-pick; empty = free text only.
    let presetModels: [String]
    /// Where to send the user to create a key (nil = unknown / derived).
    let makeGetKeyURL: @Sendable (ProviderSettings) -> String?
    /// Builds the live provider for a dictation.
    let makeProvider: @Sendable (ProviderSettings) -> PolishProvider
    /// How to verify this backend's key before dictating.
    let makeVerifyTarget: @Sendable (ProviderSettings) -> KeyVerifier.Target

    var displayName: String { backend.displayName }
    var hasConfigurableBaseURL: Bool { baseURLKeyPath != nil }
    func model(in settings: ProviderSettings) -> String { settings[keyPath: modelKeyPath] }
}

extension PolishBackendSpec {
    /// One entry per `ProviderSettings.PolishBackend`. `specForBackendTests`
    /// asserts this stays exhaustive.
    static let all: [PolishBackendSpec] = [
        PolishBackendSpec(
            backend: .openAICompatible,
            keychainKey: .polishOpenAIKey,
            modelKeyPath: \.polishModel,
            baseURLKeyPath: \.polishBaseURL,
            presetModels: [],
            makeGetKeyURL: { ProviderConsole.keyURL(forBaseURL: $0.polishBaseURL) },
            makeProvider: { settings in
                OpenAICompatibleLLM(
                    baseURL: settings.polishBaseURL,
                    model: settings.polishModel,
                    apiKey: { KeychainStore.get(.polishOpenAIKey) }
                )
            },
            makeVerifyTarget: { .openAICompatible(baseURL: $0.polishBaseURL) }
        ),
        PolishBackendSpec(
            backend: .deepseek,
            keychainKey: .polishDeepSeekKey,
            modelKeyPath: \.deepseekModel,
            baseURLKeyPath: nil,
            presetModels: ProviderSettings.deepseekModels,
            makeGetKeyURL: { _ in "https://platform.deepseek.com/api_keys" },
            makeProvider: { settings in
                OpenAICompatibleLLM(
                    baseURL: ProviderSettings.deepseekBaseURL,
                    model: settings.deepseekModel,
                    apiKey: { KeychainStore.get(.polishDeepSeekKey) }
                )
            },
            makeVerifyTarget: { _ in .openAICompatible(baseURL: ProviderSettings.deepseekBaseURL) }
        ),
        PolishBackendSpec(
            backend: .anthropic,
            keychainKey: .polishAnthropicKey,
            modelKeyPath: \.anthropicModel,
            baseURLKeyPath: nil,
            presetModels: [],
            makeGetKeyURL: { _ in "https://console.anthropic.com/settings/keys" },
            makeProvider: { settings in
                AnthropicLLM(
                    model: settings.anthropicModel,
                    apiKey: { KeychainStore.get(.polishAnthropicKey) }
                )
            },
            makeVerifyTarget: { _ in .anthropic }
        ),
        PolishBackendSpec(
            backend: .gemini,
            keychainKey: .polishGeminiKey,
            modelKeyPath: \.geminiModel,
            baseURLKeyPath: nil,
            presetModels: [],
            makeGetKeyURL: { _ in "https://aistudio.google.com/apikey" },
            makeProvider: { settings in
                GeminiLLM(
                    model: settings.geminiModel,
                    apiKey: { KeychainStore.get(.polishGeminiKey) }
                )
            },
            makeVerifyTarget: { _ in .gemini }
        ),
    ]

    static func `for`(_ backend: ProviderSettings.PolishBackend) -> PolishBackendSpec {
        // Force-unwrap is intentional: a missing spec is a wiring bug that
        // `PolishBackendSpecTests` catches immediately.
        all.first { $0.backend == backend }!
    }
}

/// Maps a known API host to its key-management console URL. Shared by the
/// polish registry and the ASR key row.
enum ProviderConsole {
    static func keyURL(forBaseURL baseURL: String) -> String? {
        let host = URL(string: baseURL)?.host() ?? baseURL
        if host.contains("openai.com") { return "https://platform.openai.com/api-keys" }
        if host.contains("groq.com") { return "https://console.groq.com/keys" }
        if host.contains("deepseek.com") { return "https://platform.deepseek.com/api_keys" }
        if host.contains("z.ai") { return "https://z.ai/manage-apikey/apikey-list" }
        if host.contains("bigmodel.cn") { return "https://open.bigmodel.cn/usercenter/apikeys" }
        return nil
    }
}
