import Foundation

/// Styles and dictionary live as JSON files in the App Group container so the
/// keyboard extension can render the style picker without the app running.
/// The app is the only writer; the keyboard only reads.
enum SharedCatalog {
    private static var stylesURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("styles.json")
    }

    private static var dictionaryURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("dictionary.json")
    }

    // MARK: Styles

    /// Built-ins followed by any custom styles the user created.
    static func loadStyles() -> [Style] {
        Style.builtIns + loadCustomStyles()
    }

    static func loadCustomStyles() -> [Style] {
        load([Style].self, from: stylesURL) ?? []
    }

    static func saveCustomStyles(_ styles: [Style]) {
        save(styles.filter { !$0.isBuiltIn }, to: stylesURL)
    }

    static func style(id: String) -> Style? {
        loadStyles().first { $0.id == id }
    }

    // MARK: Dictionary

    static func loadDictionary() -> [DictionaryEntry] {
        load([DictionaryEntry].self, from: dictionaryURL) ?? []
    }

    static func saveDictionary(_ entries: [DictionaryEntry]) {
        save(entries, to: dictionaryURL)
    }

    // MARK: Plumbing

    private static func load<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save(_ value: some Encodable, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
