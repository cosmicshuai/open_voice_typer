import SwiftUI

/// Templates (the `Style` model in code): one active at a time, mirrored by
/// the keyboard pill and the Dictate picker. Built-ins are read-only but
/// duplicable as starting points; custom templates are fully editable.
struct TemplatesView: View {
    @State private var customStyles = SharedCatalog.loadCustomStyles()
    @State private var activeStyleID = SettingsStore.load().selectedStyleID
    @State private var editingStyle: Style?

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(Style.builtIns) { style in
                        row(for: style)
                            .contextMenu {
                                Button {
                                    duplicate(style)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                            }
                    }
                }
                Section("Yours") {
                    ForEach(customStyles) { style in
                        row(for: style)
                            .contextMenu {
                                Button {
                                    editingStyle = style
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button {
                                    duplicate(style)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(style)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingStyle = style
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }
                    }
                    Button {
                        editingStyle = newTemplate()
                    } label: {
                        Label("New template", systemImage: "plus")
                            .font(.body.weight(.medium))
                    }
                }
            }
            .navigationTitle("Templates")
            .onAppear { reload() }
            .sheet(item: $editingStyle) { style in
                TemplateEditorView(style: style) { saved in
                    upsert(saved)
                }
            }
        }
    }

    private func row(for style: Style) -> some View {
        let isActive = style.id == activeStyleID
        return Button {
            activate(style)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.name.isEmpty ? "Untitled" : style.name)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(isActive ? Color.appAccent : .primary)
                    HStack(spacing: 6) {
                        Text(subtitle(for: style))
                            .lineLimit(1)
                        if style.id == Style.translate.id {
                            TemplateTag(name: "→ \(SettingsStore.load().targetLanguage)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .listRowBackground(isActive ? Color.appAccent.opacity(0.1) : nil)
    }

    private func subtitle(for style: Style) -> String {
        switch style.id {
        case Style.raw.id: "As spoken — no AI, no key needed"
        case Style.light.id: "Clean up fillers, keep your voice"
        case Style.structured.id: "Group ideas into paragraphs & lists"
        case Style.formal.id: "Business-ready phrasing"
        case Style.translate.id: "Speak one language, type another"
        default: style.instructions.replacingOccurrences(of: "\n", with: " ")
        }
    }

    // MARK: Actions

    private func activate(_ style: Style) {
        activeStyleID = style.id
        var settings = SettingsStore.load()
        settings.selectedStyleID = style.id
        if style.id != Style.translate.id {
            settings.lastDictateStyleID = style.id
        }
        SettingsStore.save(settings)
    }

    private func duplicate(_ style: Style) {
        var copy = newTemplate()
        copy.name = "\(style.name) copy"
        copy.instructions = style.instructions
        editingStyle = copy
    }

    private func newTemplate() -> Style {
        Style(id: "custom.\(UUID().uuidString)", name: "", instructions: "", isBuiltIn: false)
    }

    private func upsert(_ style: Style) {
        if let index = customStyles.firstIndex(where: { $0.id == style.id }) {
            customStyles[index] = style
        } else {
            customStyles.append(style)
        }
        SharedCatalog.saveCustomStyles(customStyles)
    }

    private func delete(_ style: Style) {
        customStyles.removeAll { $0.id == style.id }
        SharedCatalog.saveCustomStyles(customStyles)
        if activeStyleID == style.id {
            activate(.light)
        }
    }

    private func reload() {
        customStyles = SharedCatalog.loadCustomStyles()
        activeStyleID = SettingsStore.load().selectedStyleID
    }
}

/// Name + instructions, plus "Try it": one real polish call on an editable
/// spoken-style sample so a template is debuggable before saving.
private struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var style: Style
    let onSave: (Style) -> Void

    @State private var sampleInput = "uh so yesterday I mostly got the bridge PR out, um today it's keyboard input review, still stuck on that provisioning thing"
    @State private var previewOutput = ""
    @State private var previewError: String?
    @State private var isPreviewing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Standup update", text: $style.name)
                }
                Section {
                    TextEditor(text: $style.instructions)
                        .frame(minHeight: 140)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Base rules always apply: remove fillers, never answer the content, output only the final text.")
                }
                Section {
                    TextEditor(text: $sampleInput)
                        .frame(minHeight: 70)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !previewOutput.isEmpty {
                        Text(previewOutput)
                            .font(.callout)
                            .padding(.leading, 10)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(LinearGradient.brandMark)
                                    .frame(width: 3)
                            }
                    }
                    if let previewError {
                        Text(previewError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        runPreview()
                    } label: {
                        HStack {
                            if isPreviewing {
                                ProgressView().controlSize(.small)
                            }
                            Text("Run preview")
                        }
                    }
                    .disabled(isPreviewing || style.instructions.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Try it")
                } footer: {
                    Text("Runs one polish request with your current provider.")
                }
            }
            .navigationTitle(style.name.isEmpty ? "New Template" : style.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(style)
                        dismiss()
                    }
                    .disabled(style.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func runPreview() {
        isPreviewing = true
        previewError = nil
        previewOutput = ""
        let draft = style
        let sample = sampleInput

        Task {
            defer { isPreviewing = false }
            do {
                previewOutput = try await DictationPipeline(settings: SettingsStore.load())
                    .polishOnly(rawText: sample, style: draft)
            } catch {
                previewError = error.localizedDescription
            }
        }
    }
}

#Preview {
    TemplatesView()
}
