import SwiftUI

/// The keyboard's dictation surface, laid out like Typeless: brand row on
/// top (mark + Dictate/Translate toggle + context capsule), a monochrome
/// "tap to speak" pill in the middle, and utility keys (globe / undo /
/// space / delete / return) below. All colors are semantic so the panel
/// adapts to the host app's light or dark keyboard appearance.
struct VoicePanelView: View {
    @Bindable var model: VoicePanelModel
    @Namespace private var modeHighlight

    /// Punctuation that's awkward to dictate — tuned for coding and Claude
    /// Code (slash commands, @-mentions, ~paths, flags, bang, code fences).
    private let quickSymbols = ["/", "@", "~", "-", "_", "!", "#", "`"]

    var body: some View {
        VStack(spacing: 10) {
            brandRow
            Spacer(minLength: 4)
            speakArea
            Spacer(minLength: 4)
            symbolRow
            controlRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Keep controls reachable on iPad instead of stretching edge to edge.
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    // MARK: Brand row

    private var brandRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.appAccent)
                .accessibilityLabel("Voice Typer")

            Spacer(minLength: 4)

            modeToggle

            Spacer(minLength: 4)

            trailingControl
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
                .frame(width: 46, height: 28)
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
    private var trailingControl: some View {
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
            }
            .disabled(!model.canDictate)
        }
    }

    // MARK: Speak area

    @ViewBuilder
    private var speakArea: some View {
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
                .padding(.horizontal, 24)
            }
        case .idle, .recording, .processing, .error:
            VStack(spacing: 10) {
                Text(model.statusText)
                    .font(model.phase.isError ? .caption : .footnote)
                    .foregroundStyle(model.phase.isError ? .red : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Button {
                    model.toggleDictation()
                } label: {
                    ZStack {
                        Capsule()
                            .fill(
                                model.phase == .recording
                                    ? AnyShapeStyle(LinearGradient.recordingFill)
                                    : AnyShapeStyle(Color.primary)
                            )
                            .frame(width: 168, height: 56)
                            .scaleEffect(model.phase == .recording ? 1 + CGFloat(model.audioLevel) * 0.12 : 1)
                            .animation(.easeOut(duration: 0.12), value: model.audioLevel)
                            .shadow(
                                color: model.phase == .recording
                                    ? Color.red.opacity(0.35)
                                    : Color.black.opacity(0.12),
                                radius: 10, y: 4
                            )
                        if model.phase == .processing {
                            ProgressView()
                                .tint(Color(uiColor: .systemBackground))
                        } else {
                            Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(
                                    model.phase == .recording
                                        ? Color.white
                                        : Color(uiColor: .systemBackground)
                                )
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.phase == .processing)
                .accessibilityLabel(model.phase == .recording ? "Stop and insert" : "Tap to speak")
            }
        }
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
        .padding(.horizontal, 24)
    }

    // MARK: Quick symbols + controls

    /// Hard-to-dictate punctuation, one tap each.
    private var symbolRow: some View {
        HStack(spacing: 5) {
            ForEach(quickSymbols, id: \.self) { symbol in
                Button {
                    model.insertText(symbol)
                } label: {
                    Text(symbol)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insert \(symbol)")
            }
        }
    }

    /// Globe / undo / space / delete / send. Space is a normal key (dictation
    /// handles most spacing); send is accented since it's the common finish.
    private var controlRow: some View {
        HStack(spacing: 6) {
            if model.needsInputModeSwitchKey {
                utilityButton(systemImage: "globe") { model.onGlobe() }
                    .accessibilityLabel("Next keyboard")
            }
            utilityButton(systemImage: "arrow.uturn.backward") { model.undoLastInsert() }
                .disabled(!model.canUndo)
                .accessibilityLabel("Undo last insertion")
            Button {
                model.insertText(" ")
            } label: {
                Text("space")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            utilityButton(systemImage: "delete.left") { model.deleteBackward() }
                .accessibilityLabel("Delete")
            Button {
                model.insertText("\n")
            } label: {
                Text("send")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 40)
                    .background(LinearGradient.appAccentFill, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send")
        }
    }

    private func utilityButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .frame(width: 42, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
