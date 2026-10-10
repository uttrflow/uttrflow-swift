import AppKit
import SwiftUI
import UttrflowUX

@MainActor
enum PanelShortcutHelpWindow {
    private static var window: NSPanel?

    static func route(
        _ key: PanelKey,
        relativeTo parent: NSWindow,
        relay: ((PanelKey, NSRunningApplication?) -> Void)?,
        caretOwner: NSRunningApplication?
    ) {
        guard key == .showShortcuts else {
            relay?(key, caretOwner)
            return
        }
        show(relativeTo: parent)
    }

    private static func show(relativeTo parent: NSWindow) {
        let help = window ?? makeWindow()
        window = help
        if help.parent !== parent {
            if let oldParent = help.parent { oldParent.removeChildWindow(help) }
            parent.addChildWindow(help, ordered: .above)
        }
        help.setFrameOrigin(
            NSPoint(
                x: parent.frame.midX - help.frame.width / 2,
                y: parent.frame.midY - help.frame.height / 2))
        help.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.nonactivatingPanel, .titled, .closable],
            backing: .buffered, defer: false)
        panel.title = String(localized: "Keyboard Shortcuts", comment: "Shortcut guide window title.")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: PanelShortcutHelpView(onClose: close))
        return panel
    }

    private static func close() {
        guard let window else { return }
        let parent = window.parent
        window.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
    }
}

private struct PanelShortcutHelpView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(String(localized: "Quick panel shortcuts", comment: "Shortcut guide heading."))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(String(localized: "Done", comment: "Close shortcut guide."), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            Text(
                String(
                    localized: "Shortcuts depend on the selected clip and the open panel state.",
                    comment: "Shortcut availability explanation.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            ForEach(PanelShortcutCatalog.entries) { shortcut in
                HStack(spacing: 18) {
                    Text(shortcut.title)
                    Spacer(minLength: 12)
                    Text(shortcut.chord)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 520, height: 560, alignment: .topLeading)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }
}
