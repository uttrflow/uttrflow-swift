import AppKit
import UttrflowCore
import UttrflowUX
import SwiftUI

/// Whatever a row asked for, drawn.
///
/// One `switch` over a closed set, so a control the presenter can ask for and the
/// window cannot draw does not compile. Every case reports the change the presenter
/// already attached to the choice; none of them works out what a choice ought to mean.
struct SettingsControlView: View {
    let control: SettingsControl
    let isEnabled: Bool
    /// What the row says this control is for.
    ///
    /// Every control here is drawn with `labelsHidden()`, because the row already writes
    /// the label beside it — but the label passed in was `""`, so there was nothing for
    /// SwiftUI to hand to VoiceOver either. Focusing any switch in Settings announced
    /// "checkbox, checked" and named nothing. The row's own words are the right label;
    /// they were simply never given to the control.
    let label: String
    let model: SettingsViewModel

    var body: some View {
        control(for: self.control).accessibilityLabel(label)
    }

    @ViewBuilder private func control(for control: SettingsControl) -> some View {
        switch control {
        case .toggle(let field, let isOn):
            Toggle(
                "",
                isOn: Binding(
                    get: { isOn },
                    set: { model.apply(.toggle(field, isOn: $0)) })
            )
            .labelsHidden()
            .toggleStyle(SettingsSwitchStyle())

        case .applicationSwitch(let isOn, let change):
            // The same switch as `.toggle`, for a row standing for an application.
            Toggle(
                "",
                isOn: Binding(
                    get: { isOn },
                    set: { _ in model.apply(change) })
            )
            .labelsHidden()
            .toggleStyle(SettingsSwitchStyle())

        case .segmented(let options, let selectedID):
            SettingsSegmented(
                options: options.map { (id: $0.id, title: $0.title) },
                selection: selection(options, selectedID))

        case .menu(let options, let selectedID):
            SettingsMenu(
                options: options.map { (id: $0.id, title: $0.title) },
                selection: selection(options, selectedID))

        case .anchorPicker(let selected):
            SettingsAnchorPicker(selected: selected) { model.apply(.anchor($0)) }

        case .shortcut(let keys):
            SettingsShortcutField(keys: keys, model: model)

        case .tick(let isTicked, let change):
            Button {
                model.apply(change)
            } label: {
                Image(systemName: isTicked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isTicked ? Color.dockAccent : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isTicked ? [.isButton, .isSelected] : .isButton)

        case .removal(let removal):
            // Red without asking, because the case exists only for buttons that destroy
            // something. Never `.keyboardShortcut(.defaultAction)`: nothing on this
            // screen removes anything because Return was pressed.
            Button(removal.title) { model.request(removal) }
                .buttonStyle(SettingsButtonStyle(isDestructive: true))

        case .action(let title, let change):
            // Not destructive, so not red, and no confirmation: the case exists precisely
            // to keep those two treatments attached to `removal` and nothing else.
            Button(title) { model.apply(change) }
                .buttonStyle(SettingsButtonStyle(isDestructive: false))

        case .text(let value):
            // Selectable, because a version number's whole purpose is to be quoted into a
            // bug report, and one that cannot be copied has to be transcribed by hand.
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    /// A picker's selection, written back as the change the chosen option carries.
    ///
    /// The `get` falls back to the id the presenter said was selected, so a pick that
    /// is refused snaps back to the truth rather than showing a choice that was not made.
    private func selection(
        _ options: [SettingsOption], _ selectedID: String
    ) -> Binding<String> {
        Binding(
            get: { selectedID },
            set: { picked in
                guard let option = options.first(where: { $0.id == picked }) else { return }
                model.apply(option.change)
            })
    }
}

// MARK: - Where the button parks

/// The four corners the floating button can park in, drawn as a small screen.
struct SettingsAnchorPicker: View {
    let selected: DockAnchor
    let onSelect: (DockAnchor) -> Void

    var body: some View {
        ZStack {
            // The screen the button parks on, in this window's own colours. It was a
            // lilac gradient left over from the palette before the identity was teal,
            // and it was the one thing on the pane that belonged to no scheme at all.
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.settingsControl)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.mainSeparator, lineWidth: 1))
            ForEach(DockAnchor.allCases, id: \.self) { anchor in
                dot(anchor)
            }
        }
        .frame(width: 46, height: 29)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Where the floating button parks")
    }

    private func dot(_ anchor: DockAnchor) -> some View {
        let isSelected = anchor == selected
        return Button {
            onSelect(anchor)
        } label: {
            Circle()
                .fill(isSelected ? Color.settingsAccentInk : Color.mainDim)
                .frame(width: 5, height: 5)
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.settingsAccentInk.opacity(0.45) : .clear, lineWidth: 2)
                )
                // A five-point dot is not a target. The hit area is the whole quadrant.
                .padding(6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(anchor))
        .padding(5)
        .accessibilityLabel(Self.name(of: anchor))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func alignment(_ anchor: DockAnchor) -> Alignment {
        switch anchor {
        case .bottomLeft: .bottomLeading
        case .bottomCentre: .bottom
        case .bottomRight: .bottomTrailing
        case .rightEdge: .trailing
        }
    }

    /// Spoken, because a dot in a rectangle says nothing to VoiceOver.
    static func name(of anchor: DockAnchor) -> String {
        switch anchor {
        case .bottomLeft: "Bottom left"
        case .bottomCentre: "Bottom centre"
        case .bottomRight: "Bottom right"
        case .rightEdge: "Right edge"
        }
    }
}

// MARK: - The shortcut

/// The shortcut, and the field that records a new one.
///
/// Keystrokes are taken through a local event monitor rather than SwiftUI's focus
/// machinery because the combinations worth recording — ⌘Q, ⌥Space — are the ones the
/// menus and the responder chain would otherwise eat before any view saw them. The
/// monitor is installed only while recording and swallows what it takes, so nothing
/// pressed at the field reaches the rest of the app.
struct SettingsShortcutField: View {
    let keys: [String]
    let model: SettingsViewModel

    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            if model.session.recorder.isRecording {
                Text(model.session.recorder.prompt)
                    .font(.system(size: SettingsMetrics.calloutSize))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    keycap(key)
                }
            }
            Button(model.session.recorder.isRecording ? "Cancel" : "Change") {
                if model.session.recorder.isRecording {
                    model.cancelRecordingShortcut()
                } else {
                    model.beginRecordingShortcut()
                }
            }
            .buttonStyle(SettingsButtonStyle())
        }
        .onChange(of: model.session.recorder.isRecording, initial: true) { _, isRecording in
            isRecording ? startListening() : stopListening()
        }
        .onDisappear(perform: stopListening)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation shortcut, \(keys.joined(separator: " "))")
    }

    /// A key drawn as a key, the way the last page of first-run draws the same shortcut.
    /// The two windows are showing the user the same physical thing.
    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(minWidth: 30, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.settingsControl)
                    .shadow(color: .black.opacity(0.30), radius: 0, y: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.mainSeparator, lineWidth: 1))
    }

    private func startListening() {
        guard monitor == nil else { return }
        // `.flagsChanged` as well as `.keyDown`, because a modifier pressed on its own
        // sends only the former. Without it, somebody trying to bind ⌘ or Fn alone — the
        // obvious thing to try on a dictation app, and what several of them use — pressed
        // their key and the field said nothing at all: no shortcut, no refusal, just
        // "Press the new shortcut" for ever. Silence reads as a broken field, not as a
        // rule. Such a binding is genuinely undeliverable, so it is still refused; the
        // change is that now it is refused *out loud*.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let modifiers = SettingsShortcutField.modifiers(from: event.modifierFlags)

            guard event.type == .flagsChanged else {
                model.record(keyCode: event.keyCode, modifiers: modifiers)
                // Swallowed: nothing pressed at this field should reach the rest of the app.
                return nil
            }

            // Fn is a shortcut in its own right — held, not combined — so it is recorded
            // rather than refused. It carries none of the four modifiers this app names,
            // so it has to be recognised by its own flag before the empty-modifier check
            // below would throw the press away as a release.
            if event.keyCode == HotkeyBinding.functionKeyCode,
                event.modifierFlags.contains(.function)
            {
                model.record(keyCode: event.keyCode, modifiers: [])
                return event
            }

            // `.flagsChanged` fires on the release too, where the flags have gone empty.
            // Only the press is an attempt at a shortcut; reporting the release as one
            // would answer a single tap with two different complaints.
            //
            // A modifier-only press — ⌃⌥, or ⌘ on its own — arrives here with the flags
            // set and a modifier's own key code, and is recorded as the hold it is. That
            // used to fall through to the refusal below, which is why ⌃⌥ answered a
            // perfectly reasonable request with "Try a letter, a number or Space".
            guard !modifiers.isEmpty else { return event }
            model.record(keyCode: event.keyCode, modifiers: modifiers)
            // Passed on, unlike a key press: swallowing a modifier change would leave the
            // rest of the app believing a key is still held after the user let go.
            return event
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Cocoa's flags reduced to the four the product recognises. Everything else — Caps
    /// Lock, Fn, the numeric-keypad bit — is noise the window server sets on its own.
    static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<HotkeyModifier> {
        var modifiers: Set<HotkeyModifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
