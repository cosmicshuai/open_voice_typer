import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var model: VoicePanelModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = VoicePanelModel(needsInputModeSwitchKey: needsInputModeSwitchKey)
        model.onGlobe = { [weak self] in self?.advanceToNextInputMode() }
        model.insertTextHandler = { [weak self] text in self?.textDocumentProxy.insertText(text) }
        model.deleteBackwardHandler = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        self.model = model

        // Paint the input view itself with the panel's wash tone. Some hosts
        // (iMessage) leave a band at the top of the keyboard that the SwiftUI
        // content doesn't cover; if that band is inside our input view it
        // shows this color instead of the host's gray. (safeAreaRegions = []
        // makes the hosting content ignore host safe-area insets too.)
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.16, blue: 0.20, alpha: 1)
                : UIColor(red: 0.886, green: 0.894, blue: 0.949, alpha: 1)
        }

        let panel = UIHostingController(rootView: VoicePanelView(model: model).tint(Color.appAccent))
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        panel.view.backgroundColor = .clear
        panel.safeAreaRegions = []
        addChild(panel)
        view.addSubview(panel.view)
        panel.didMove(toParent: self)

        // The keyboard's height is set on the INPUT VIEW itself; the panel
        // just fills it. It matches the standard iPhone keyboard height:
        // hosts like iMessage reserve a fixed keyboard frame and bottom-align
        // a shorter input view inside it, leaving a gray band on top — so the
        // input view must be tall enough to fill that frame. Priority 999
        // keeps it from fighting the system's transient constraints.
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 240)
        heightConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            panel.view.topAnchor.constraint(equalTo: view.topAnchor),
            panel.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model?.activate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        model?.deactivate()
        super.viewWillDisappear(animated)
    }
}
