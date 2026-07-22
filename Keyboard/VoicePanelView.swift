import SwiftUI

/// The keyboard's dictation surface, laid out like Typeless: brand row on
/// top (name + style capsule), a monochrome "tap to speak" pill in the
/// middle, and utility keys (globe / undo / space / delete / return) below.
/// All colors are semantic so the panel adapts to the host app's light or
/// dark keyboard appearance.
struct VoicePanelView: View {
    @Bindable var model: VoicePanelModel

    var body: some View {
        VStack(spacing: 8) {
            brandRow
            Spacer(minLength: 0)
            speakArea
            Spacer(minLength: 0)
            utilityRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Keep controls reachable on iPad instead of stretching edge to edge.
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    // MARK: Brand row

    private var brandRow: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.appAccent)
                Text("Voice Typer")
                    .font(.footnote.weight(.semibold))
            }

            Spacer()

            Menu {
                ForEach(model.styles) { style in
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
            guidance(
                icon: "iphone.app.switcher",
                title: "Open Open Voice Typer",
                message: "Opening the app starts the mic session automatically — then switch back here and speak."
            )
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
                            .fill(model.phase == .recording ? Color.red : Color.primary)
                            .frame(width: 168, height: 56)
                            .scaleEffect(model.phase == .recording ? 1 + CGFloat(model.audioLevel) * 0.12 : 1)
                            .animation(.easeOut(duration: 0.12), value: model.audioLevel)
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

    // MARK: Utility row

    private var utilityRow: some View {
        HStack(spacing: 8) {
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
                Text("return")
                    .font(.subheadline)
                    .frame(width: 76, height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return")
        }
    }

    private func utilityButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .frame(width: 44, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
