import AppKit
import SwiftUI
import UttrflowCore
import UttrflowUX

/// Whatever a row asked for, drawn as one switch over a closed set. See `Docs/app-settings-controls.md`.
struct SettingsControlView: View {
    let control: SettingsControl
    let isEnabled: Bool
    /// What the row says this control is for; the control hides its own label, so VoiceOver needs this.
    let label: String
    let model: SettingsViewModel

    var body: some View {
        switch control {
        case .segmented:
            // Each option names itself; one label over the pair reads as two identical buttons.
            view(for: control)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
        case .action, .removal:
            // A button names itself, so the row it acts on is the hint: "Resume, button. Pause for a while".
            view(for: control).accessibilityHint(label)
        default:
            view(for: control).accessibilityLabel(label)
        }
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

        case .shortcut(let action, let keys):
            SettingsShortcutField(action: action, keys: keys, model: model)

        case .tick(let isTicked, let change):
            Button {
                model.apply(change)
            } label: {
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isTicked ? PagePalette.dictation : PagePalette.faint)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isTicked ? [.isButton, .isSelected] : .isButton)

        case .removal(let removal):
            // Red without asking; never the default action, since Return must not remove anything.
            Button(removal.title) { model.request(removal) }
                .buttonStyle(SettingsButtonStyle(isDestructive: removal.reset == .everything))

        case .action(let title, let change):
            // Not destructive, so not red and not confirmed: both belong to `removal` alone.
            Button {
                model.apply(change)
            } label: {
                if case .pauseSuggestions(isOn: true) = change {
                    Label(title, systemImage: "pause")
                        .labelStyle(SettingsLeadingIconLabelStyle())
                } else {
                    Text(title)
                }
            }
            .buttonStyle(SettingsButtonStyle(isDestructive: false))

        case .text(let value):
            // Selectable, because a version number exists to be quoted into a bug report.
            Text(value)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(SettingsPalette.ink(0.7))
                .textSelection(.enabled)

        case .placeholder(let value):
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(SettingsPalette.ink(0.5))

        case .status(let value):
            SettingsStatusView(text: value)

        case .languages(let chips, let add):
            HStack(spacing: 6) {
                ForEach(chips) { chip in
                    SettingsChipView(
                        title: chip.title,
                        onRemove: chip.removal.map { removal in { model.apply(removal) } })
                }
                if !add.isEmpty {
                    Menu {
                        ForEach(add) { option in
                            Button(option.title) { model.apply(option.change) }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(SettingsLeadingIconLabelStyle())
                            .font(.system(size: 12.5))
                            .foregroundStyle(PagePalette.text)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(SettingsPalette.ink(0.08), in: .capsule)
                            .overlay(Capsule().strokeBorder(SettingsPalette.ink(0.12), lineWidth: 1))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Add a language")
                }
            }
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

// MARK: - The shortcut

/// The shortcut and the field that records a new one. See `Docs/app-settings-controls.md`.
struct SettingsShortcutField: View {
    let action: ShortcutAction
    let keys: [String]
    let model: SettingsViewModel

    /// Recording belongs to one row, so the others keep showing their keys.
    private var isRecording: Bool {
        model.session.recorder.isRecording && model.session.recorder.action == action
    }

    /// The local monitor that owns candidate keystrokes before the menu or responder chain sees them.
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            if isRecording {
                // Listening: the old keys dimmed inside a lit box, and a ghost key for the next one.
                HStack(spacing: 6) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                        SettingsKeycap(key: key).opacity(0.3)
                    }
                    SettingsKeycap(key: " ").opacity(0.3)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(PagePalette.dictation.opacity(0.1), in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PagePalette.dictation, lineWidth: 1.5)
                )
                .shadow(color: PagePalette.dictation.opacity(0.5), radius: 9)
                Button("Cancel") { model.cancelRecordingShortcut() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(SettingsPalette.ink(0.6))
            } else {
                if keys.isEmpty {
                    Text("None")
                        .font(.system(size: 12.5))
                        .foregroundStyle(PagePalette.faint)
                } else {
                    SettingsKeys(keys: keys)
                }
                Button {
                    model.beginRecordingShortcut(action)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(SettingsLeadingIconLabelStyle())
                }
                .buttonStyle(SettingsButtonStyle())
            }
        }
        .onChange(of: isRecording, initial: true) { _, recording in
            recording ? startListening() : stopListening()
        }
        .onDisappear(perform: stopListening)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            SettingsShortcut.accessibilityLabel(for: action, keys: keys, isRecording: isRecording))
    }

    private func startListening() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
        let label = SettingsShortcut.accessibilityLabel(for: action, keys: keys, isRecording: true)
        NSAccessibility.post(
            element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: label, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        switch Self.route(event) {
        case .recordAndConsume(let stroke):
            model.receive(stroke)
            return nil
        case .recordAndPass(let stroke):
            model.receive(stroke)
            return event
        case .pass:
            return event
        }
    }

    static func route(_ event: NSEvent) -> ShortcutRecorderEventRoute {
        switch event.type {
        case .keyDown:
            .recordAndConsume(stroke(from: event, phase: .down))
        case .flagsChanged:
            .recordAndPass(stroke(from: event, phase: .modifiersChanged))
        default:
            .pass
        }
    }

    static func stroke(from event: NSEvent, phase: KeyPhase) -> KeyStroke {
        let modifiers = modifiers(from: event.modifierFlags)
        let isFunctionDown = event.modifierFlags.contains(.function)
        let keyCode = UInt16(event.keyCode)
        return KeyStroke(
            keyCode: keyCode, modifiers: modifiers, isFunctionDown: isFunctionDown, phase: phase,
            isKeyDown: isDown(
                keyCode: keyCode, phase: phase, modifiers: modifiers,
                isFunctionDown: isFunctionDown))
    }

    static func isDown(
        keyCode: UInt16, phase: KeyPhase, modifiers: Set<HotkeyModifier>, isFunctionDown: Bool
    ) -> Bool {
        switch phase {
        case .down: true
        case .up: false
        case .modifiersChanged:
            if keyCode == HotkeyBinding.functionKeyCode {
                isFunctionDown
            } else if let named = HotkeyBinding.modifier(ofKeyCode: keyCode) {
                modifiers.contains(named)
            } else {
                false
            }
        }
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

enum ShortcutRecorderEventRoute: Equatable {
    case recordAndConsume(KeyStroke)
    case recordAndPass(KeyStroke)
    case pass
}
