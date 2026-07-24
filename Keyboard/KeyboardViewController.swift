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

        let panel = UIHostingController(rootView: VoicePanelView(model: model).tint(Color.appAccent))
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        panel.view.backgroundColor = .clear
        // Some hosts (iMessage) hand the keyboard a top safe-area inset that
        // Safari doesn't. Left in place, the hosting controller insets the
        // SwiftUI content — and its background wash — leaving a gray strip at
        // the top of the panel. Ignoring safe areas lets the wash fill the
        // input view edge to edge.
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
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 291)
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
