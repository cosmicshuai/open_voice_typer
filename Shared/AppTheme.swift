import SwiftUI
import UIKit

/// App identity colors, shared by the app and the keyboard extension.
extension Color {
    /// Petrol teal accent — distinct from stock iOS blue, keeps the red
    /// recording state unmistakable. Light #0E7583, dark #3FB2C0.
    static let appAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x3F / 255, green: 0xB2 / 255, blue: 0xC0 / 255, alpha: 1)
            : UIColor(red: 0x0E / 255, green: 0x75 / 255, blue: 0x83 / 255, alpha: 1)
    })
}
