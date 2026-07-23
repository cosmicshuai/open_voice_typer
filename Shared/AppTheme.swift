import SwiftUI
import UIKit

/// App identity colors, shared by the app and the keyboard extension.
extension Color {
    /// Indigo accent — harmonizes with the navy of the app icon and reads
    /// "AI product" rather than green, while keeping the red recording state
    /// unmistakable. Light #4A52E8, dark #7E86FA.
    static let appAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x7E / 255, green: 0x86 / 255, blue: 0xFA / 255, alpha: 1)
            : UIColor(red: 0x4A / 255, green: 0x52 / 255, blue: 0xE8 / 255, alpha: 1)
    })

    /// Lighter companion to `appAccent`, used as the top stop of gradients
    /// so filled controls catch the light instead of reading flat.
    static let appAccentLight = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xA4 / 255, green: 0xAA / 255, blue: 0xFF / 255, alpha: 1)
            : UIColor(red: 0x70 / 255, green: 0x78 / 255, blue: 0xF2 / 255, alpha: 1)
    })

    /// Key-cap fill for the keyboard's tappable keys — bright and elevated
    /// like system keyboard keys, instead of a flat translucent gray.
    static let keyCap = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor.white
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
