import AppKit

import UttrflowUX

/// The menu bar item and its menu, drawing a ``MenuBarPresentation`` and deciding nothing itself.
@MainActor
final class MenuBarController: NSObject {
    /// Everything a click on this menu can mean, as one channel so a new row needs no new wiring.
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

    /// Drops the menu open as though clicked, for the failure whose fix is "the words are in here".
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
            // Only when the symbol is missing from the running OS; a blank slot has nothing to click.
            button.title = button.image == nil ? "Uttrflow" : ""
        }
        statusItem.menu = buildMenu()
    }

    /// The icon: a template except when something needs attention, where the colour is the message.
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
        // A template image is recoloured by the menu bar, so keeping the tint means opting out.
        tinted.isTemplate = false
        return tinted
    }

    /// The mark at menu bar size, as a template so the bar inverts and dims it like every neighbour.
    private static func markImage(describedAs description: String) -> NSImage? {
        guard let image = Bundle.module.image(forResource: "MenuBarIconTemplate")
        else { return nil }
        image.isTemplate = true
        // 18pt tall, what AppKit gives a menu bar symbol, at the mark's own 62:72 proportions.
        image.size = NSSize(width: 18 * (62.0 / 72.0), height: 18)
        image.accessibilityDescription = description
        return image
    }

    /// The system's orange rather than the design's flat swatch, so a warning survives dark contrast.
    private static let attentionColour = NSColor.systemOrange

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // Enablement says what the product can do, so no responder may switch an item back on.
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
            Self.statusMenuItem(text: text, emphasis: emphasis)
        case .command(let command):
            commandItem(for: command)
        }
    }

    private static func statusMenuItem(text: String, emphasis: MenuBarEmphasis) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = statusDot(for: emphasis)
        if emphasis == .attention {
            // Attributed, because a warning drawn in disabled grey is a warning nobody sees.
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
        // Set explicitly: an item defaults to ⌘ with no key, printing a shortcut and breaking pairing.
        item.keyEquivalentModifierMask = Self.modifiers(command.shortcut?.modifiers ?? [])
        item.isEnabled = command.isEnabled
        item.isAlternate = command.isAlternate
        item.toolTip = command.tooltip
        // A tick, so a switch reads as a switch rather than as a command that runs twice.
        item.state = command.isChecked ? .on : .off
        item.representedObject = command.intent
        return item
    }

    /// Every modifier, switched over `allCases` so the next one added is a build failure, not a typo.
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
