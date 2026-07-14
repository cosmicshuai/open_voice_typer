import SwiftUI

/// Built-in styles are read-only; custom style packs (name + instructions)
/// can be created, edited, and deleted. Persisted to the App Group container
/// so the keyboard's style picker sees them too.
struct StylesView: View {
    @State private var customStyles = SharedCatalog.loadCustomStyles()
    @State private var editingStyle: Style?

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(Style.builtIns) { style in
                        row(for: style)
                    }
                }
                Section("Custom") {
                    ForEach(customStyles) { style in
                        Button {
                            editingStyle = style
                        } label: {
                            row(for: style)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        customStyles.remove(atOffsets: offsets)
                        SharedCatalog.saveCustomStyles(customStyles)
                    }
                }
            }
            .navigationTitle("Styles")
            .toolbar {
                Button {
                    editingStyle = Style(
                        id: "custom.\(UUID().uuidString)",
                        name: "",
                        instructions: "",
                        isBuiltIn: false
                    )
                } label: {
                    Label("Add style", systemImage: "plus")
                }
            }
            .sheet(item: $editingStyle) { style in
                StyleEditorView(style: style) { saved in
                    if let index = customStyles.firstIndex(where: { $0.id == saved.id }) {
                        customStyles[index] = saved
                    } else {
                        customStyles.append(saved)
                    }
                    SharedCatalog.saveCustomStyles(customStyles)
                }
            }
        }
    }

    private func row(for style: Style) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(style.name.isEmpty ? "Untitled" : style.name)
            if !style.instructions.isEmpty {
                Text(style.instructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if style.id == Style.raw.id {
                Text("Transcript as-is — no AI polish, no API key needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StyleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var style: Style
    let onSave: (Style) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Casual chat", text: $style.name)
                }
                Section {
                    TextEditor(text: $style.instructions)
                        .frame(minHeight: 160)
                        .font(.body)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Describe how the transcript should be reshaped. The base cleanup rules (remove fillers, never answer the content) always apply.")
                }
            }
            .navigationTitle(style.name.isEmpty ? "New Style" : style.name)
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
}

#Preview {
    StylesView()
}
