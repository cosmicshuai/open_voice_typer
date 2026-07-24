import SwiftUI

/// The keyboard's dictation surface, laid out like Typeless: a header with the
/// brand mark and context control on the left and the Dictate/Translate toggle
/// on the right; then a centered stadium mic with a `return` pill beneath it,
/// and the secondary keys in a column pinned to the trailing edge. All colors
/// are semantic so the panel adapts to the host app's light or dark keyboard.
struct VoicePanelView: View {
    @Bindable var model: VoicePanelModel
    @Namespace private var modeHighlight

    // Typeless's proportions, measured off its keyboard at 393pt wide and kept
    // fixed rather than proportional: these are thumb targets, so they should
    // not grow with the screen the way a layout container would.
    private let micSize = CGSize(width: 136, height: 62)
    private let returnSize = CGSize(width: 112, height: 42)
    private let utilityKeySide: CGFloat = 36

    var body: some View {
        VStack(spacing: 8) {
            headerRow
            Spacer(minLength: 6)
            actionCluster
            // Typeless settles `return` near the panel's bottom edge rather
            // than centering the cluster in the leftover space. Capping the
            // trailing spacer sends the slack to the flexible one above, so a
            // host that hands us a tall frame grows the gap under the header
            // instead of stranding the keys in the middle.
            Spacer(minLength: 0).frame(maxHeight: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Keep controls reachable on iPad instead of stretching edge to edge.
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        // Deliberately no background: the panel sits directly on the system
        // keyboard material supplied by the `UIInputView` in
        // KeyboardViewController, so iMessage's container band above us and the
        // globe row below are the same backdrop with no visible seam. Anything
        // opaque here — even a subtle wash — reintroduces that seam. The brand
        // lives in the colored controls instead.
    }

    /// Elevated key-cap look shared by all tappable keys — white (or lifted
    /// gray in dark keyboards) with a crisp edge shadow, like system keys.
    private func keycap(cornerRadius: CGFloat = 9) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.keyCap)
            .shadow(color: .black.opacity(0.22), radius: 0.5, y: 1)
    }

    // MARK: Header

    /// Mark + context on the left, mode toggle hard right — Typeless's header
    /// split. The toggle no longer needs the centering overlay it used to use,
    /// because it's now pinned to an edge rather than floated in the middle.
    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(LinearGradient.brandMark)
                .accessibilityLabel("Voice Typer")

            contextControl

            Spacer(minLength: 8)

            modeToggle
        }
    }

    /// Dictate (waveform) | Translate (dictionary), with a gradient thumb
    /// that slides between them and the active glyph animating on select.
    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeSegment("waveform", label: "Dictate", mode: .dictate)
            modeSegment("character.book.closed", label: "Translate", mode: .translate)
        }
        .padding(3)
        .background(.quaternary, in: Capsule())
        .disabled(!model.canDictate)
    }

    private func modeSegment(_ systemImage: String, label: String, mode: VoicePanelModel.Mode) -> some View {
        let isOn = model.mode == mode
        return Button {
            withAnimation(.spring(duration: 0.3)) {
                model.setMode(mode)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .frame(width: 40, height: 28)
                .background {
                    if isOn {
                        Capsule()
                            .fill(LinearGradient.appAccentFill)
                            .matchedGeometryEffect(id: "thumb", in: modeHighlight)
                    }
                }
                .foregroundStyle(isOn ? .white : .primary)
                // Animate the glyph whenever this segment becomes active.
                .symbolEffect(.bounce, value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Dictate mode: the template picker. Translate mode: where the words
    /// will land (target language is configured in the app's Settings).
    @ViewBuilder
    private var contextControl: some View {
        if model.mode == .translate {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
                Text(model.targetLanguage)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.appAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.appAccent.opacity(0.14), in: Capsule())
        } else {
            Menu {
                ForEach(model.dictateStyles) { style in
                    Button {
                        model.selectedStyleID = style.id
                    } label: {
                        if style.id == model.selectedStyleID {
                            Label(style.name, systemImage: "checkmark")
                        } else {
                            Text(style.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text(model.selectedStyleName)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.appAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appAccent.opacity(0.14), in: Capsule())
            }
            .disabled(!model.canDictate)
        }
    }

    // MARK: Action cluster

    /// Typeless's arrangement: the primary control and `return` stacked down
    /// the panel's centerline, with the secondary keys in a column pinned to
    /// the trailing edge. Overlaying that column instead of giving it a row of
    /// its own is what keeps the mic optically centered and lets the keys span
    /// the mic and `return` rows the way Typeless's do.
    private var actionCluster: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 10) {
                primaryArea
                returnKey
            }
            .frame(maxWidth: .infinity)

            utilityColumn
        }
    }

    @ViewBuilder
    private var primaryArea: some View {
        switch model.phase {
        case .noFullAccess:
            guidance(
                icon: "lock.shield",
                title: "Allow Full Access",
                message: "Settings → General → Keyboard → Keyboards → Voice Typer → Allow Full Access"
            )
        case .noSession:
            // A SwiftUI Link is the only reliable way to open the containing
            // app from a keyboard extension on iOS 18+ — Apple broke the old
            // selector/openURL responder-chain hack, and extensions can't call
            // UIApplication.open. Needs Full Access.
            Link(destination: VoicePanelModel.openAppURL) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.title2)
                    Text("Open Voice Typer")
                        .font(.subheadline.weight(.semibold))
                    Text("The mic turned off. Tap to reopen the app — it restarts automatically, then swipe back here to speak.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.appAccent)
                // Clear the utility column so the copy never runs under it.
                .padding(.horizontal, utilityKeySide + 16)
            }
        case .idle, .recording, .processing, .error:
            VStack(spacing: 10) {
                Text(model.statusText)
                    .font(model.phase.isError ? .caption : .footnote)
                    .foregroundStyle(model.phase.isError ? .red : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, utilityKeySide + 16)

                micKey
            }
        }
    }

    /// The stadium mic — Typeless's shape. A wide capsule is a much larger
    /// tap target than the circle it replaces at the same height, which is the
    /// point: this is the one control the user hits every time.
    private var micKey: some View {
        Button {
            model.toggleDictation()
        } label: {
            ZStack {
                Capsule()
                    .fill(
                        model.phase == .recording
                            ? LinearGradient.recordingFill
                            : LinearGradient.appAccentFill
                    )
                    .overlay(
                        // Hairline top-lit rim so the button reads as a glossy
                        // dome, not a flat disc (redesign recipe).
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8)
                            .blendMode(.plusLighter)
                    )
                    .frame(width: micSize.width, height: micSize.height)
                    .scaleEffect(model.phase == .recording ? 1 + CGFloat(model.audioLevel) * 0.08 : 1)
                    .animation(.easeOut(duration: 0.12), value: model.audioLevel)
                    .shadow(
                        color: model.phase == .recording
                            ? Color.red.opacity(0.5)
                            : Color.appAccent.opacity(0.5),
                        radius: 11, y: 8
                    )
                if model.phase == .processing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .processing)
        .accessibilityLabel(model.phase == .recording ? "Stop and insert" : "Tap to speak")
    }

    /// Inserts a newline — which is what "send" means in a chat host like
    /// iMessage. Named `return` after the key it actually is, as Typeless does.
    private var returnKey: some View {
        Button {
            model.insertText("\n")
        } label: {
            Text("return")
                .font(.subheadline.weight(.medium))
                .frame(width: returnSize.width, height: returnSize.height)
                .background { keycap(cornerRadius: returnSize.height / 2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Return")
    }

    /// Delete and undo, stacked at the trailing edge. Typeless puts an "@" in
    /// the lower slot; undo is the better use of it here — the model already
    /// tracks the last insertion, and after a long dictation lands wrong,
    /// one tap beats holding delete.
    private var utilityColumn: some View {
        VStack(spacing: 10) {
            utilityKey("delete.left", label: "Delete") {
                model.deleteBackward()
            }
            utilityKey("arrow.uturn.backward", label: "Undo dictation") {
                model.undoLastInsert()
            }
            .disabled(!model.canUndo)
            .opacity(model.canUndo ? 1 : 0.4)
        }
    }

    private func utilityKey(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote)
                .frame(width: utilityKeySide, height: utilityKeySide)
                .background { keycap(cornerRadius: utilityKeySide / 2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func guidance(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        // Clear the utility column so the copy never runs under it.
        .padding(.horizontal, utilityKeySide + 16)
    }
}
