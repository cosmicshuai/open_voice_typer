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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model?.activate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        model?.deactivate()
        super.viewWillDisappear(animated)
    }
}
