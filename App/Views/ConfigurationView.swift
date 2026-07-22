import SwiftUI

/// Provider configuration, grouped by pipeline stage in the order data flows:
/// speech-to-text → polish → the session that powers the keyboard. Key status
/// is a first-class state (Missing / Unverified / Verified), never a mystery.
struct ConfigurationView: View {
    @State private var settings = SettingsStore.load()
    @State private var editingKey: KeyEditorContext?
    /// Bumped after the key sheet closes so status badges re-read the store.
    @State private var keyStateVersion = 0

    var body: some View {
        NavigationStack {
            Form {
                asrSection
                polishSection
                sessionSection
                translateSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onChange(of: settings) { SettingsStore.save(settings) }
            .sheet(item: $editingKey, onDismiss: { keyStateVersion += 1 }) { context in
                KeyEditorSheet(context: context)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: Speech to text

    private var asrSection: some View {
        Section {
            Picker("Engine", selection: $settings.asrBackend) {
                Text("On-device").tag(ProviderSettings.ASRBackend.apple)
                Text("Cloud").tag(ProviderSettings.ASRBackend.openAICompatible)
            }
            .pickerStyle(.segmented)
            if settings.asrBackend == .openAICompatible {
                presetRow(ProviderPreset.asr) { preset in
                    settings.asrBaseURL = preset.baseURL
                    settings.asrModel = preset.model
                }
                LabeledContent("Base URL") {
                    plainField("https://api.openai.com/v1", text: $settings.asrBaseURL)
                }
                LabeledContent("Model") {
                    plainField("gpt-4o-transcribe", text: $settings.asrModel)
                }
                keyRow("API Key", key: .asrAPIKey, target: .openAICompatible(baseURL: settings.asrBaseURL),
                       getKeyURL: keyConsoleURL(forBaseURL: settings.asrBaseURL))
            }
            LabeledContent("Language") {
                plainField("auto", text: $settings.asrLanguage)
            }
        } header: {
            Text("Speech to text")
        } footer: {
            settings.asrBackend == .apple
                ? Text("Free, offline, no key needed — Apple on-device recognition. Language is an ISO-639 hint like “en” or “zh”; empty auto-detects.")
                : Text("Any OpenAI-compatible endpoint: OpenAI, Groq, etc.")
        }
    }

    // MARK: Polish

    private var polishSection: some View {
        Section {
            Picker("Provider", selection: $settings.polishBackend) {
                ForEach(ProviderSettings.PolishBackend.allCases, id: \.self) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            switch settings.polishBackend {
            case .openAICompatible:
                presetRow(ProviderPreset.polish) { preset in
                    settings.polishBaseURL = preset.baseURL
                    settings.polishModel = preset.model
                }
                LabeledContent("Base URL") {
                    plainField("https://api.openai.com/v1", text: $settings.polishBaseURL)
                }
                LabeledContent("Model") {
                    plainField("gpt-4o-mini", text: $settings.polishModel)
                }
                keyRow("API Key", key: .polishOpenAIKey, target: .openAICompatible(baseURL: settings.polishBaseURL),
                       getKeyURL: keyConsoleURL(forBaseURL: settings.polishBaseURL))
            case .deepseek:
                Menu {
                    ForEach(ProviderSettings.deepseekModels, id: \.self) { model in
                        Button(model) { settings.deepseekModel = model }
                    }
                } label: {
                    LabeledContent("Preset") {
                        HStack(spacing: 4) {
                            Text("Choose…")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(Color.appAccent)
                    }
                }
                LabeledContent("Model") {
                    plainField("deepseek-v4-flash", text: $settings.deepseekModel)
                }
                keyRow("API Key", key: .polishDeepSeekKey,
                       target: .openAICompatible(baseURL: ProviderSettings.deepseekBaseURL),
                       getKeyURL: "https://platform.deepseek.com/api_keys")
            case .anthropic:
                LabeledContent("Model") {
                    plainField("claude-sonnet-5", text: $settings.anthropicModel)
                }
                keyRow("API Key", key: .polishAnthropicKey, target: .anthropic,
                       getKeyURL: "https://console.anthropic.com/settings/keys")
            case .gemini:
                LabeledContent("Model") {
                    plainField("gemini-2.5-flash", text: $settings.geminiModel)
                }
                keyRow("API Key", key: .polishGeminiKey, target: .gemini,
                       getKeyURL: "https://aistudio.google.com/apikey")
            }
        } header: {
            Text("Polish")
        } footer: {
            Text("Keys live in the iOS Keychain and are only read by this app — never by the keyboard.")
        }
    }

    // MARK: Session / Translate / About

    private var sessionSection: some View {
        Section {
            Picker("Auto-end after", selection: $settings.sessionAutoEndMinutes) {
                ForEach(ProviderSettings.autoEndChoices, id: \.minutes) { choice in
                    Text(choice.label).tag(choice.minutes)
                }
            }
        } header: {
            Text("Keyboard session")
        } footer: {
            Text("A running session keeps the microphone active so the keyboard can dictate. Auto-ending limits battery use if you forget to stop it.")
        }
    }

    private var translateSection: some View {
        Section("Translate template") {
            LabeledContent("Target language") {
                plainField("English", text: $settings.targetLanguage)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            }
            Link(destination: URL(string: "https://github.com/cosmicshuai/open_voice_typer")!) {
                LabeledContent("Source") { Text("GitHub") }
            }
        }
    }

    // MARK: Pieces

    private func presetRow(
        _ presets: [ProviderPreset],
        apply: @escaping (ProviderPreset) -> Void
    ) -> some View {
        Menu {
            ForEach(presets) { preset in
                Button(preset.name) { apply(preset) }
            }
        } label: {
            LabeledContent("Preset") {
                HStack(spacing: 4) {
                    Text("Choose…")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Color.appAccent)
            }
        }
    }

    /// Where to create an API key, recognized from the endpoint host.
    private func keyConsoleURL(forBaseURL baseURL: String) -> String? {
        let host = URL(string: baseURL)?.host() ?? baseURL
        if host.contains("openai.com") { return "https://platform.openai.com/api-keys" }
        if host.contains("groq.com") { return "https://console.groq.com/keys" }
        if host.contains("deepseek.com") { return "https://platform.deepseek.com/api_keys" }
        if host.contains("z.ai") { return "https://z.ai/manage-apikey/apikey-list" }
        if host.contains("bigmodel.cn") { return "https://open.bigmodel.cn/usercenter/apikeys" }
        return nil
    }

    private func keyRow(
        _ label: String,
        key: KeychainStore.Key,
        target: KeyVerifier.Target,
        getKeyURL: String? = nil
    ) -> some View {
        // keyStateVersion invalidates this row when the sheet saves a key.
        let status = KeyStatusStore.status(for: key)
        _ = keyStateVersion
        return Button {
            editingKey = KeyEditorContext(key: key, target: target, getKeyURL: getKeyURL)
        } label: {
            LabeledContent(label) {
                switch status {
                case .missing:
                    Label("Missing", systemImage: "circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                case .unverified:
                    Text("Saved — not verified")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .verified:
                    Label("Verified", systemImage: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .tint(.primary)
    }

    private func plainField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
    }
}

// MARK: - Key editor sheet

private struct KeyEditorContext: Identifiable {
    let key: KeychainStore.Key
    let target: KeyVerifier.Target
    let getKeyURL: String?
    var id: String { key.rawValue }
}

/// Paste, verify (free list-models call), and save a key.
private struct KeyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let context: KeyEditorContext

    @State private var keyText: String
    @State private var isVerifying = false
    @State private var verifyError: String?

    init(context: KeyEditorContext) {
        self.context = context
        _keyText = State(initialValue: KeychainStore.get(context.key) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Paste your API key", text: $keyText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Verification makes one free request (list models) — it never spends tokens.")
                }
                if let verifyError {
                    Section {
                        Text(verifyError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        verifyAndSave()
                    } label: {
                        HStack {
                            if isVerifying { ProgressView().controlSize(.small) }
                            Text("Verify & Save")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isVerifying || keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Save without verifying") {
                        saveOnly()
                        dismiss()
                    }
                    .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove key", role: .destructive) {
                        KeychainStore.delete(context.key)
                        KeyStatusStore.clear(context.key)
                        dismiss()
                    }
                    .disabled(KeychainStore.get(context.key) == nil)
                }
                if let getKeyURL = context.getKeyURL, let url = URL(string: getKeyURL) {
                    Section {
                        Link("Get an API key", destination: url)
                    }
                }
            }
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func saveOnly() {
        KeychainStore.set(keyText, for: context.key)
        KeyStatusStore.clear(context.key)
    }

    private func verifyAndSave() {
        isVerifying = true
        verifyError = nil
        let trimmed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            defer { isVerifying = false }
            do {
                try await KeyVerifier.verify(key: trimmed, target: context.target)
                KeychainStore.set(trimmed, for: context.key)
                KeyStatusStore.markVerified(context.key)
                dismiss()
            } catch {
                // Key is kept in the field so the user can still save it unverified.
                verifyError = error.localizedDescription
            }
        }
    }
}

#Preview {
    ConfigurationView()
}
