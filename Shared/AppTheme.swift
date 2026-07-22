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

    /// Lighter companion to `appAccent`, used as the top stop of gradients
    /// so filled controls catch the light instead of reading flat.
    static let appAccentLight = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x6B / 255, green: 0xD3 / 255, blue: 0xDF / 255, alpha: 1)
            : UIColor(red: 0x2A / 255, green: 0x9D / 255, blue: 0xAD / 255, alpha: 1)
    })
}

extension LinearGradient {
    /// Brand fill for prominent controls (mic button, hero marks).
    static let appAccentFill = LinearGradient(
        colors: [.appAccentLight, .appAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Recording fill — warm red with the same lighting direction.
    static let recordingFill = LinearGradient(
        colors: [Color(red: 1.0, green: 0.36, blue: 0.32), Color(red: 0.86, green: 0.13, blue: 0.18)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
