import SwiftUI

/// The keyboard's dictation surface: style pill + undo on top, Speak button
/// in the middle, utility row (globe / space / backspace / return) below.
struct VoicePanelView: View {
    @Bindable var model: VoicePanelModel

    var body: some View {
        VStack(spacing: 10) {
            topBar
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

    private var topBar: some View {
        HStack {
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

            Spacer()

            Button {
                model.undoLastInsert()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
            .disabled(!model.canUndo)
            .accessibilityLabel("Undo last insertion")
        }
    }

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
                title: "Start a session",
                message: "Open Open Voice Typer and start a keyboard session, then come back."
            )
        case .idle, .recording, .processing, .error:
            VStack(spacing: 6) {
                Button {
                    model.toggleDictation()
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.phase == .recording ? Color.red : Color.appAccent)
                            .frame(width: 64, height: 64)
                            .scaleEffect(model.phase == .recording ? 1 + CGFloat(model.audioLevel) * 0.3 : 1)
                            .animation(.easeOut(duration: 0.12), value: model.audioLevel)
                        if model.phase == .processing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.phase == .processing)

                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(model.phase.isError ? .red : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
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

    private var utilityRow: some View {
        HStack(spacing: 8) {
            if model.needsInputModeSwitchKey {
                utilityButton(systemImage: "globe") { model.onGlobe() }
                    .accessibilityLabel("Next keyboard")
            }
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
            utilityButton(systemImage: "return") { model.insertText("\n") }
                .accessibilityLabel("Return")
        }
    }

    private func utilityButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .frame(width: 52, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
