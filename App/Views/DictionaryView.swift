import SwiftUI

/// Proper nouns and phrases the recognizer keeps mishearing. Fed to ASR as
/// hotwords and to the polish prompt as exact-spelling vocabulary.
struct DictionaryView: View {
    @State private var entries = SharedCatalog.loadDictionary()
    @State private var newTerm = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add a name or term…", text: $newTerm)
                            .autocorrectionDisabled()
                            .onSubmit(addTerm)
                        Button(action: addTerm) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Example: product names, teammates, jargon — “XcodeGen”, “Wispr”, “Shuai”.")
                }

                Section {
                    ForEach(entries) { entry in
                        Text(entry.term)
                    }
                    .onDelete { offsets in
                        entries.remove(atOffsets: offsets)
                        SharedCatalog.saveDictionary(entries)
                    }
                }
            }
            .navigationTitle("Dictionary")
        }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        guard !entries.contains(where: { $0.term.caseInsensitiveCompare(term) == .orderedSame }) else {
            newTerm = ""
            return
        }
        entries.insert(DictionaryEntry(term: term), at: 0)
        SharedCatalog.saveDictionary(entries)
        newTerm = ""
    }
}

#Preview {
    DictionaryView()
}
