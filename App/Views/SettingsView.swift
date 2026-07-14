import SwiftUI

/// Provider configuration. Non-secret settings persist via SettingsStore
/// (App Group defaults); API keys go straight to the Keychain.
struct SettingsView: View {
    @State private var settings = SettingsStore.load()
    @State private var asrKey = KeychainStore.get(.asrAPIKey) ?? ""
    @State private var openAIKey = KeychainStore.get(.polishOpenAIKey) ?? ""
    @State private var anthropicKey = KeychainStore.get(.polishAnthropicKey) ?? ""
    @State private var geminiKey = KeychainStore.get(.polishGeminiKey) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                asrSection
                polishSection
                translationSection
            }
            .navigationTitle("Settings")
            .onChange(of: settings) { SettingsStore.save(settings) }
        }
    }

    private var asrSection: some View {
        Section {
            Picker("Engine", selection: $settings.asrBackend) {
                ForEach(ProviderSettings.ASRBackend.allCases, id: \.self) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            if settings.asrBackend == .openAICompatible {
                LabeledContent("Base URL") {
                    urlField("https://api.openai.com/v1", text: $settings.asrBaseURL)
                }
                LabeledContent("Model") {
                    plainField("gpt-4o-transcribe", text: $settings.asrModel)
                }
                keyField("API Key", text: $asrKey, keychainKey: .asrAPIKey)
            }
            LabeledContent("Language") {
                plainField("auto", text: $settings.asrLanguage)
            }
        } header: {
            Text("Speech to Text")
        } footer: {
            settings.asrBackend == .apple
                ? Text("On-device recognition. Free, offline, no API key needed.")
                : Text("Any OpenAI-compatible endpoint: OpenAI, Groq, etc. Language is an ISO-639 hint like “en” or “zh”; leave empty to auto-detect.")
        }
    }

    private var polishSection: some View {
        Section {
            Picker("Provider", selection: $settings.polishBackend) {
                ForEach(ProviderSettings.PolishBackend.allCases, id: \.self) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            switch settings.polishBackend {
            case .openAICompatible:
                LabeledContent("Base URL") {
                    urlField("https://api.openai.com/v1", text: $settings.polishBaseURL)
                }
                LabeledContent("Model") {
                    plainField("gpt-4o-mini", text: $settings.polishModel)
                }
                keyField("API Key", text: $openAIKey, keychainKey: .polishOpenAIKey)
            case .anthropic:
                LabeledContent("Model") {
                    plainField("claude-sonnet-5", text: $settings.anthropicModel)
                }
                keyField("API Key", text: $anthropicKey, keychainKey: .polishAnthropicKey)
            case .gemini:
                LabeledContent("Model") {
                    plainField("gemini-2.5-flash", text: $settings.geminiModel)
                }
                keyField("API Key", text: $geminiKey, keychainKey: .polishGeminiKey)
            }
        } header: {
            Text("Polish")
        } footer: {
            Text("Reshapes the transcript per the selected style. Keys are stored in the iOS Keychain and only read by this app — never by the keyboard.")
        }
    }

    private var translationSection: some View {
        Section {
            LabeledContent("Target language") {
                plainField("English", text: $settings.targetLanguage)
            }
        } header: {
            Text("Translate style")
        }
    }

    // MARK: Field helpers

    private func plainField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }

    private func urlField(_ placeholder: String, text: Binding<String>) -> some View {
        plainField(placeholder, text: text)
            .keyboardType(.URL)
    }

    private func keyField(_ label: String, text: Binding<String>, keychainKey: KeychainStore.Key) -> some View {
        SecureField(label, text: text)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: text.wrappedValue) {
                KeychainStore.set(text.wrappedValue, for: keychainKey)
            }
    }
}

#Preview {
    SettingsView()
}
