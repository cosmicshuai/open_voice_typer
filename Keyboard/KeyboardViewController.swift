import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let panel = UIHostingController(rootView: VoicePanelPlaceholderView(
            needsInputModeSwitchKey: needsInputModeSwitchKey,
            onGlobe: { [weak self] in self?.advanceToNextInputMode() }
        ))
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        panel.view.backgroundColor = .clear
        addChild(panel)
        view.addSubview(panel.view)
        panel.didMove(toParent: self)

        NSLayoutConstraint.activate([
            panel.view.topAnchor.constraint(equalTo: view.topAnchor),
            panel.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.view.heightAnchor.constraint(equalToConstant: 260),
        ])
    }
}

/// Placeholder panel; replaced by the real voice panel in a later PR.
struct VoicePanelPlaceholderView: View {
    let needsInputModeSwitchKey: Bool
    let onGlobe: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 44))
            Text("Voice Typer")
                .font(.headline)
            if needsInputModeSwitchKey {
                Button(action: onGlobe) {
                    Image(systemName: "globe")
                        .font(.title2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
