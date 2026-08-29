import AppKit

import UttrflowUX

/// The menu bar item and its menu.
///
/// Deliberately thin. It decides nothing — not what the menu contains, not what a click
/// means, and not whether an item may be chosen. All of that arrives in a
/// ``MenuBarPresentation`` that a test has already checked, so the icon, the status line
/// and VoiceOver can never disagree with the floating button about the same moment. What
/// is left here is drawing: an SF Symbol, a colour, and an `NSMenuItem` per row.
@MainActor
final class MenuBarController: NSObject {
    /// Everything a click on this menu can mean.
    ///
    /// One channel rather than a closure per item: the presentation already says what
    /// each row does, so adding a row does not add a property here to forget to wire.
    var onCommand: ((MenuBarIntent) -> Void)?

    private let statusItem: NSStatusItem
    private var presentation: MenuBarPresentation

    init(
        statusBar: NSStatusBar = .system,
        initial: MenuBarPresentation = MenuBarPresenter.present(MenuBarState())
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        presentation = initial
        super.init()
        apply()
    }

    /// Shows a new moment. Cheap enough to call on every state change.
    func update(with presentation: MenuBarPresentation) {
        self.presentation = presentation
        apply()
    }

    /// Drops the menu open as though the item had been clicked.
    ///
    /// For the one failure whose fix is "the words are over here": the clipboard route
    /// failed, so the only place left holding the text is the Recent section of this
    /// menu, and a button that says "Show Recent" has to actually show it.
    func openMenu() {
        statusItem.button?.performClick(nil)
    }

    /// Gives the slot back. Without it the item lingers until the process dies.
    func removeFromMenuBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Rendering

    private func apply() {
        if let button = statusItem.button {
            button.image = Self.icon(for: presentation)
            button.setAccessibilityLabel(presentation.accessibilityLabel)
            // Only reached if the symbol is missing from the running OS; a blank slot in
            // the menu bar would leave the user with nothing to click.
            button.title = button.image == nil ? "Uttrflow" : ""
        }
        statusItem.menu = buildMenu()
    }

    /// The icon: a template so the system draws it correctly on a light or dark menu bar,
    /// except when something needs attention, where the colour *is* the message.
    private static func icon(for presentation: MenuBarPresentation) -> NSImage? {
        let resolved: NSImage? =
            switch presentation.icon {
            case .mark: markImage(describedAs: presentation.accessibilityLabel)
            case .symbol(let name):
                NSImage(
                    systemSymbolName: name,
                    accessibilityDescription: presentation.accessibilityLabel)
            }
        guard let image = resolved else { return nil }

        guard presentation.isAttentionNeeded else { return image }

        guard let tinted = image.withSymbolConfiguration(.init(paletteColors: [attentionColour]))
        else { return image }
        // A template image is recoloured by the menu bar; keeping the tint means opting
        // out of that.
        tinted.isTemplate = false
        return tinted
    }

    /// The mark, at menu bar size.
    ///
    /// Marked as a template so the system inverts it for a light or dark bar and dims it
    /// while the menu is open — the same treatment every system icon beside it gets.
    /// `nil` if the resource is missing, which `apply()` turns into a titled slot rather
    /// than an empty one.
    private static func markImage(describedAs description: String) -> NSImage? {
        guard let image = Bundle.module.image(forResource: "MenuBarIconTemplate")
        else { return nil }
        image.isTemplate = true
        // 18pt tall, the height AppKit gives a menu bar symbol, at the mark's own
        // 62:72 proportions — setting only a square would letterbox it.
        image.size = NSSize(width: 18 * (62.0 / 72.0), height: 18)
        image.accessibilityDescription = description
        return image
    }

    /// The system's orange rather than the flat swatch in the design, so the warning stays
    /// legible when the menu is drawn dark or with increased contrast.
    private static let attentionColour = NSColor.systemOrange

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // Enablement says what the product can do, not whether a responder happens to
        // handle a selector — so nothing may switch an item back on behind our back.
        menu.autoenablesItems = false
        for item in presentation.items {
            menu.addItem(menuItem(for: item))
        }
        return menu
    }

    private func menuItem(for item: MenuBarItem) -> NSMenuItem {
        switch item {
        case .separator:
            .separator()
        case .sectionHeader(let title):
            .sectionHeader(title: title)
        case .status(let text, let emphasis):
            Self.statusItem(text: text, emphasis: emphasis)
        case .command(let command):
            commandItem(for: command)
        }
    }

    private static func statusItem(text: String, emphasis: MenuBarEmphasis) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = statusDot(for: emphasis)
        if emphasis == .attention {
            // Attributed, because a disabled item is drawn grey and a warning that reads
            // as unavailable text is a warning nobody sees.
            item.attributedTitle = NSAttributedString(
                string: text,
                attributes: [.foregroundColor: attentionColour, .font: NSFont.menuFont(ofSize: 0)])
        }
        return item
    }

    private func commandItem(for command: MenuBarCommand) -> NSMenuItem {
        let item = NSMenuItem(
            title: command.title, action: #selector(runCommand(_:)),
            keyEquivalent: command.shortcut?.key ?? "")
        item.target = self
        // Set explicitly: an item defaults to ⌘ even with no key, which both prints a
        // stray shortcut and stops an alternate item from pairing with the row above it.
        item.keyEquivalentModifierMask = Self.modifiers(command.shortcut?.modifiers ?? [])
        item.isEnabled = command.isEnabled
        item.isAlternate = command.isAlternate
        item.toolTip = command.tooltip
        item.representedObject = command.intent
        return item
    }

    /// Every modifier, not the ones somebody remembered. This was three `if`s, and when
    /// `.shift` joined the model for the clipboard's ⇧⌘V no fourth `if` joined it here —
    /// so the menu printed ⌘V and bound ⌘V, which is paste. Switching over `allCases`
    /// turns the next addition into a build failure rather than a wrong key on screen.
    static func modifiers(_ modifiers: MenuBarModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for modifier in MenuBarModifier.allCases where modifiers.contains(modifier) {
            switch modifier {
            case .command: flags.insert(.command)
            case .option: flags.insert(.option)
            case .shift: flags.insert(.shift)
            }
        }
        return flags
    }

    /// The coloured dot beside the status line.
    private static func statusDot(for emphasis: MenuBarEmphasis) -> NSImage? {
        let colour: NSColor =
            switch emphasis {
            case .attention: attentionColour
            case .live: .systemRed
            case .normal: .systemGreen
            }

        let dot = NSImage(systemSymbolName: "circlebadge.fill", accessibilityDescription: nil)
        let image = dot?.withSymbolConfiguration(.init(paletteColors: [colour]))
        image?.isTemplate = false
        return image
    }

    // MARK: - Menu actions

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let intent = sender.representedObject as? MenuBarIntent else { return }
        onCommand?(intent)
    }
}
