import Foundation

/// Provider and pipeline configuration. Lives in App Group defaults so the
/// keyboard can read the selected style; API keys are NOT here — they stay in
/// the app-only Keychain.
struct ProviderSettings: Codable, Equatable, Sendable {
    enum ASRBackend: String, Codable, CaseIterable, Sendable {
        case apple
        case openAICompatible

        var displayName: String {
            switch self {
            case .apple: "Apple (on-device)"
            case .openAICompatible: "OpenAI-compatible"
            }
        }
    }

    enum PolishBackend: String, Codable, CaseIterable, Sendable {
        case openAICompatible
        case anthropic
        case gemini

        var displayName: String {
            switch self {
            case .openAICompatible: "OpenAI-compatible"
            case .anthropic: "Anthropic"
            case .gemini: "Google Gemini"
            }
        }
    }

    var asrBackend: ASRBackend = .apple
    var asrBaseURL: String = "https://api.openai.com/v1"
    var asrModel: String = "gpt-4o-transcribe"
    /// ISO-639 hint for ASR; empty = auto-detect / current locale.
    var asrLanguage: String = ""

    var polishBackend: PolishBackend = .openAICompatible
    var polishBaseURL: String = "https://api.openai.com/v1"
    var polishModel: String = "gpt-4o-mini"
    var anthropicModel: String = "claude-sonnet-5"
    var geminiModel: String = "gemini-2.5-flash"

    var selectedStyleID: String = Style.light.id
    var targetLanguage: String = "English"
}

enum SettingsStore {
    private static let key = "settings.providers"

    static func load() -> ProviderSettings {
        guard let data = AppGroup.defaults?.data(forKey: key),
              let settings = try? JSONDecoder().decode(ProviderSettings.self, from: data)
        else { return ProviderSettings() }
        return settings
    }

    static func save(_ settings: ProviderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        AppGroup.defaults?.set(data, forKey: key)
    }
}
