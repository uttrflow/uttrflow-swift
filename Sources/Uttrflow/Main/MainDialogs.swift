// The glass notice, the centred confirmation sheet, and the buttons and tile both are built from.

import UttrflowUX
import SwiftUI

extension MainTone {
    /// The colour a notice or a sheet glows and tints its tile in.
    var glow: Color {
        switch self {
        case .neutral, .accent: PagePalette.dictation
        case .warning: PagePalette.clipboard
        case .good: PagePalette.success
        case .critical: PagePalette.critical
        }
    }
}

/// A symbol on a rounded square washed in its colour, as notices and sheets open with.
struct MainTintedTile: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(color.opacity(0.32), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

/// How big a dialog button is drawn: the sheet's regular size or a notice's compact one.
enum MainDialogButtonSize {
    case regular
    case compact

    var font: Font { .system(size: self == .regular ? 13 : 12, weight: .semibold) }
    var horizontal: CGFloat { self == .regular ? 16 : 12 }
    var vertical: CGFloat { self == .regular ? 8 : 6 }
}

/// The button that goes ahead: solid when harmless, a red wash when it destroys something.
struct MainPrimaryButtonStyle: ButtonStyle {
    var isDestructive = false
    var size = MainDialogButtonSize.regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(isDestructive ? PagePalette.destructiveInk : PagePalette.primaryInk)
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDestructive ? PagePalette.critical.opacity(0.16) : PagePalette.primaryFill)
            }
            .overlay {
                if isDestructive {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(PagePalette.critical.opacity(0.4), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.rect)
    }
}

/// The button that changes nothing: a faint fill and a hairline edge.
struct MainSecondaryButtonStyle: ButtonStyle {
    var size = MainDialogButtonSize.regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .regular ? 13 : 12, weight: .medium))
            .foregroundStyle(PagePalette.text)
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PagePalette.quietFill.opacity(configuration.isPressed ? 2 : 1))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PagePalette.controlEdge, lineWidth: 1)
            }
            .contentShape(.rect)
    }
}

/// The question a button asks before it acts, centred over a veiled window; Return and Escape both cancel.
struct ConfirmationSheet: View {
    let confirmation: MainConfirmation
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        ZStack {
            ConfirmationBackdrop()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            // Takes every click, so nothing behind the question can be pressed while it is asked.
            PagePalette.scrim
                .contentShape(.rect)
                .onTapGesture {}
                .accessibilityHidden(true)
            card
        }
        .transition(.opacity)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                MainTintedTile(symbolName: confirmation.symbolName, color: confirmation.tone.glow)
                VStack(alignment: .leading, spacing: 4) {
                    Text(confirmation.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PagePalette.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(confirmation.message)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(PagePalette.text.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                // Cancel is the default, so Return never destroys anything.
                Button(confirmation.cancelTitle, action: onCancel)
                    .buttonStyle(MainSecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button(confirmation.confirmTitle, action: onConfirm)
                    .buttonStyle(MainPrimaryButtonStyle(isDestructive: confirmation.isDestructive))
            }
            .background {
                Button("", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(PagePalette.sheetGlass, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(PagePalette.controlEdge, lineWidth: 1)
        }
        .shadow(color: PagePalette.floatShadow, radius: 30, y: 30)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Blurs the window behind a live sheet without asking offscreen renderers to draw AppKit material.
private struct ConfirmationBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfirmationBackdropHost {
        ConfirmationBackdropHost()
    }

    func updateNSView(_ view: ConfirmationBackdropHost, context: Context) {}
}

/// Installs the native material only after SwiftUI attaches the sheet to its live window.
private final class ConfirmationBackdropHost: NSView {
    private var effect: NSVisualEffectView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            effect?.removeFromSuperview()
            effect = nil
            return
        }
        guard effect == nil else { return }

        let effect = NSVisualEffectView(frame: bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .fullScreenUI
        effect.blendingMode = .withinWindow
        effect.state = .active
        addSubview(effect)
        self.effect = effect
    }
}

/// The question waiting to be answered in the main window, and the intent that answering yes sends.
@MainActor
@Observable
final class MainConfirmationCenter {
    /// What is being asked, if anything.
    private(set) var pending: (confirmation: MainConfirmation, intent: MainIntent)?

    /// Asks before `intent` is sent.
    func ask(_ confirmation: MainConfirmation, before intent: MainIntent) {
        pending = (confirmation, intent)
    }

    /// Takes the question down, handing back the intent to send when the answer was yes.
    func answer(confirming: Bool) -> MainIntent? {
        defer { pending = nil }
        return confirming ? pending?.intent : nil
    }

    /// Presses `action`: asks through `center` first when the action needs a yes, otherwise sends it.
    static func press(
        _ action: MainAction, in center: MainConfirmationCenter?, onIntent: (MainIntent) -> Void
    ) {
        if let confirmation = action.confirmation, let center {
            center.ask(confirmation, before: action.intent)
        } else {
            onIntent(action.intent)
        }
    }
}

extension View {
    /// Draws the main window's pending question over this view, sending its intent on a yes.
    func confirmationSheet(
        _ center: MainConfirmationCenter, onIntent: @escaping (MainIntent) -> Void
    ) -> some View {
        overlay {
            if let pending = center.pending {
                ConfirmationSheet(
                    confirmation: pending.confirmation,
                    onCancel: { _ = center.answer(confirming: false) },
                    onConfirm: {
                        if let intent = center.answer(confirming: true) { onIntent(intent) }
                    })
            }
        }
        .animation(.easeOut(duration: 0.15), value: center.pending?.confirmation)
        .environment(center)
    }
}
