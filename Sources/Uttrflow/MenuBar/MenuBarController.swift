import AppKit
import SwiftUI

import UttrflowCore
import UttrflowUX

/// A borderless, non-activating panel that takes the keyboard while open, so the popover works without a pointer.
final class MenuBarPanel: NSPanel {
    /// Called when Escape reaches the panel.
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// The popover's hosting view, taking the first click because another app is always frontmost.
final class MenuBarHostingView: NSHostingView<MenuBarPopoverView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The menu bar item, its popover and its right-click menu, drawing a ``MenuBarPresentation`` and deciding nothing itself.
@MainActor
final class MenuBarController: NSObject {
    /// Everything a click in the popover or its menu can mean, as one channel so a new row needs no new wiring.
    var onCommand: ((MenuBarIntent) -> Void)?
    /// Called as the popover or menu opens, early enough that an update made here is what it shows.
    var onMenuWillOpen: (() -> Void)?

    private let statusItem: NSStatusItem
    private let isDevelopmentBuild: Bool
    /// What the menu bar shows now; readable so a test can check what the app drew.
    private(set) var presentation: MenuBarPresentation
    /// The right-click menu, refilled in place, so an update made while it opens lands in the menu on screen.
    private let menu = NSMenu()
    private let panel: MenuBarPanel
    private let hostingView: MenuBarHostingView
    /// Clicks and Escape anywhere else close the popover, as a menu would.
    private var monitors: [Any] = []

    /// Whether the popover is on screen.
    var isPopoverShown: Bool { panel.isVisible }

    /// Whether the popover's view draws anything, which it does only while the panel is on screen.
    var isPopoverContentHosted: Bool { hostingView.rootView.isShown }

    /// Signed out: a click asks for sign-in instead of opening the popover, and the menu offers only that and Quit.
    var requiresSignIn = false {
        didSet { if requiresSignIn { closePopover() } }
    }

    init(
        statusBar: NSStatusBar = .system,
        initial: MenuBarPresentation = MenuBarPresenter.present(MenuBarState()),
        buildIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        isDevelopmentBuild = UttrflowBuildIdentity.isDevelopmentBuild(buildIdentifier)
        presentation = initial
        hostingView = MenuBarHostingView(
            rootView: MenuBarPopoverView(presentation: initial, onCommand: { _ in }, isShown: false))
        panel = MenuBarPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        super.init()
        configurePanel()
        // Enablement says what the product can do, so no responder may switch an item back on.
        menu.autoenablesItems = false
        menu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        apply()
    }

    /// Shows a new moment. Cheap enough to call on every state change.
    func update(with presentation: MenuBarPresentation) {
        self.presentation = presentation
        apply()
    }

    /// Drops the popover open as though clicked, for the failure whose fix is "the words are in here".
    func openMenu() {
        guard !requiresSignIn else { return askToSignIn() }
        showPopover()
    }

    /// The one thing a click does while signed out.
    private func askToSignIn() {
        closePopover()
        onCommand?(.open(.onboarding))
    }

    /// Gives the slot back. Without it the item lingers until the process dies.
    func removeFromMenuBar() {
        closePopover()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Rendering

    private func apply() {
        if let button = statusItem.button {
            button.image = Self.icon(for: presentation, isDevelopmentBuild: isDevelopmentBuild)
            let label =
                isDevelopmentBuild
                ? "Uttrflow Dev, \(presentation.accessibilityLabel)" : presentation.accessibilityLabel
            button.setAccessibilityLabel(label)
            button.attributedTitle = Self.title(
                isDevelopmentBuild: isDevelopmentBuild, iconMissing: button.image == nil)
        }
        fillMenu()
        // A closed popover stays empty until it opens, so a hidden panel never starts an animation.
        guard panel.isVisible else { return }
        hostPresentation()
        placePanel()
    }

    /// Puts the current presentation in the popover.
    private func hostPresentation() {
        hostingView.rootView = MenuBarPopoverView(presentation: presentation) { [weak self] intent in
            self?.run(intent)
        }
    }

    /// The icon: a template except when something needs attention, where the colour is the message.
    static func icon(for presentation: MenuBarPresentation, isDevelopmentBuild: Bool = false) -> NSImage? {
        let resolved: NSImage? =
            switch presentation.icon {
            case .mark: markImage(describedAs: presentation.accessibilityLabel)
            case .symbol(let name):
                NSImage(
                    systemSymbolName: name,
                    accessibilityDescription: presentation.accessibilityLabel)
            }
        guard let image = resolved else { return nil }

        let colour: NSColor
        if presentation.isAttentionNeeded {
            colour = attentionColour
        } else if isDevelopmentBuild {
            colour = developmentColour
        } else {
            return image
        }

        guard let tinted = image.withSymbolConfiguration(.init(paletteColors: [colour]))
        else { return image }
        // A template image is recoloured by the menu bar, so keeping the tint means opting out.
        tinted.isTemplate = false
        return tinted
    }

    static func title(isDevelopmentBuild: Bool, iconMissing: Bool) -> NSAttributedString {
        let title =
            iconMissing
            ? (isDevelopmentBuild ? "Uttrflow Dev" : "Uttrflow") : (isDevelopmentBuild ? "Dev" : "")
        let attributes: [NSAttributedString.Key: Any] =
            isDevelopmentBuild ? [.foregroundColor: NSColor.systemBlue] : [:]
        return NSAttributedString(string: title, attributes: attributes)
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
    private static let developmentColour = NSColor.systemBlue

    // MARK: - The popover

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The glass draws its own shadow; the window's would be a rectangle round the margin.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hostingView
        panel.setAccessibilityLabel("Uttrflow")
        panel.onCancel = { [weak self] in self?.closePopover() }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            closePopover()
            // Lent to the item for one click, so the menu drops from the bar as a native one does.
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else if requiresSignIn {
            askToSignIn()
        } else if panel.isVisible {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard !panel.isVisible else { return }
        onMenuWillOpen?()
        hostPresentation()
        placePanel()
        panel.orderFrontRegardless()
        // Key without activating, so the keyboard and VoiceOver reach the popover and the app underneath stays frontmost.
        panel.makeKey()
        statusItem.button?.highlight(true)
        watchForDismissal()
    }

    /// Orders the panel out and empties it, since a hidden panel's content keeps animating.
    func closePopover() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        hostingView.rootView = MenuBarPopoverView(
            presentation: presentation, onCommand: { _ in }, isShown: false)
        statusItem.button?.highlight(false)
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    /// Sizes the panel to the view and hangs it under the icon, kept on the icon's screen.
    private func placePanel() {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let margin = MenuBarPopoverView.shadowMargin
        guard let buttonWindow = statusItem.button?.window else { return }
        let icon = buttonWindow.frame
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? icon
        var x = icon.midX - size.width / 2
        x = min(max(x, visible.minX - margin + 8), visible.maxX - size.width + margin - 8)
        let top = icon.minY - 6 + margin
        panel.setFrame(
            NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// Closes on a click outside the popover or on Escape, the two ways a menu is dismissed.
    private func watchForDismissal() {
        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }
        let inside = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            let number = event.windowNumber
            MainActor.assumeIsolated { self?.closeUnlessOwn(windowNumber: number) }
            return event
        }
        let escape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.closePopover() }
        }
        monitors = [outside, inside, escape].compactMap(\.self)
    }

    /// Closes for a click in another of the app's windows; the icon's own click toggles instead.
    private func closeUnlessOwn(windowNumber: Int) {
        guard windowNumber != panel.windowNumber,
            windowNumber != statusItem.button?.window?.windowNumber
        else { return }
        closePopover()
    }

    /// Closes first, so a paste lands in the app underneath rather than racing the popover.
    private func run(_ intent: MenuBarIntent) {
        closePopover()
        onCommand?(intent)
    }

    // MARK: - The right-click menu

    private func fillMenu() {
        menu.removeAllItems()
        for item in presentation.items {
            menu.addItem(menuItem(for: item))
        }
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

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        onMenuWillOpen?()
    }
}

// MARK: - The popover's right-click menu

/// The right-click menu's switches, windows and Quit, drawn from the same items the icon's menu shows.
struct MenuBarMenuItems: View {
    let items: [MenuBarItem]
    let onCommand: (MenuBarIntent) -> Void

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            switch item {
            case .status, .sectionHeader:
                EmptyView()
            case .separator:
                Divider()
            case .command(let command):
                if command.isChecked {
                    Button {
                        onCommand(command.intent)
                    } label: {
                        Label(command.title, systemImage: "checkmark")
                    }
                    .disabled(!command.isEnabled)
                } else {
                    Button(command.title) { onCommand(command.intent) }.disabled(!command.isEnabled)
                }
            }
        }
    }
}
