import AppKit
import UttrflowCore
import UttrflowUX
import SwiftUI

/// Whatever a row asked for, drawn as one switch over a closed set. See `Docs/app-settings-controls.md`.
struct SettingsControlView: View {
    let control: SettingsControl
    let isEnabled: Bool
    /// What the row says this control is for; the control hides its own label, so VoiceOver needs this.
    let label: String
    let model: SettingsViewModel

    var body: some View {
        view(for: control).accessibilityLabel(label)
    }

    /// The one control a settings row asked for.
    @ViewBuilder private func view(for control: SettingsControl) -> some View {
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
            // Red without asking; never the default action, since Return must not remove anything.
            Button(removal.title) { model.request(removal) }
                .buttonStyle(SettingsButtonStyle(isDestructive: true))

        case .action(let title, let change):
            // Not destructive, so not red and not confirmed: both belong to `removal` alone.
            Button(title) { model.apply(change) }
                .buttonStyle(SettingsButtonStyle(isDestructive: false))

        case .text(let value):
            // Selectable, because a version number exists to be quoted into a bug report.
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    /// A picker's selection; the get answers the presenter's id, so a refused pick snaps back.
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
            // The screen the button parks on, in this window's own colours.
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

/// The shortcut and the field that records a new one. See `Docs/app-settings-controls.md`.
struct SettingsShortcutField: View {
    let keys: [String]
    let model: SettingsViewModel

    @State private var monitor: Any?

    /// A modifier held with nothing yet pressed against it, waiting to see which shortcut it becomes.
    @State private var pendingHeld: UInt16?

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

    /// A key drawn as a key, matching first-run so both windows show the same physical thing.
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
        // `.flagsChanged` too, so a modifier pressed alone is refused out loud rather than in silence.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let modifiers = SettingsShortcutField.modifiers(from: event.modifierFlags)

            guard event.type == .flagsChanged else {
                pendingHeld = nil
                model.record(keyCode: event.keyCode, modifiers: modifiers)
                // Swallowed: nothing pressed at this field should reach the rest of the app.
                return nil
            }

            // Fn is a shortcut in its own right and carries none of the four modifiers named below.
            if event.keyCode == HotkeyBinding.functionKeyCode,
                event.modifierFlags.contains(.function)
            {
                pendingHeld = nil
                model.record(keyCode: event.keyCode, modifiers: [])
                return event
            }

            // A modifier down waits: it is a shortcut of its own only if nothing is pressed against it.
            guard !modifiers.isEmpty else {
                // Released with nothing pressed against it, so the modifier was the whole shortcut.
                if let held = pendingHeld {
                    pendingHeld = nil
                    model.record(keyCode: held, modifiers: [])
                }
                return event
            }
            pendingHeld = event.keyCode
            // Passed on, unlike a key press: the rest of the app must not think a key is still held.
            return event
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Cocoa's flags reduced to the four the product recognises; the rest is window-server noise.
    static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<HotkeyModifier> {
        var modifiers: Set<HotkeyModifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
