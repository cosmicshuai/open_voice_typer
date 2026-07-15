import Foundation

/// Identifiers shared between the main app and the keyboard extension.
enum AppGroup {
    static let identifier = "group.com.shuaiwang.openvoicetyper"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
