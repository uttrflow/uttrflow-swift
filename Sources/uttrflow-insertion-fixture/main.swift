// A test-only window whose three fields misbehave on purpose, driven by `Scripts/e2e_insertion.sh`; see `Docs/insertion.md`.
import AppKit

/// The command line, read once; an unknown value exits with status 2.
struct FixtureOptions {
    let mode: FixtureMode
    let focus: String
    let report: URL

    init(_ arguments: [String]) {
        var values: [String: String] = [:]
        var remaining = arguments[...]
        while let name = remaining.popFirst(), let value = remaining.popFirst() { values[name] = value }
        guard let mode = FixtureMode(rawValue: values["--mode"] ?? "faithful"),
            let report = values["--report"],
            ["text", "multiline", "secure"].contains(values["--focus"] ?? "text")
        else {
            let modes = FixtureMode.allCases.map(\.rawValue).joined(separator: "|")
            FileHandle.standardError.write(
                Data("usage: --mode <\(modes)> --focus <text|multiline|secure> --report <path>\n".utf8))
            exit(2)
        }
        self.mode = mode
        self.focus = values["--focus"] ?? "text"
        self.report = URL(fileURLWithPath: report)
    }
}

/// Owns the window and writes the report whenever a field changes.
@MainActor
final class Fixture: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let options: FixtureOptions
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 260), styleMask: [.titled], backing: .buffered,
        defer: false)
    let text = FixtureTextView(frame: NSRect(x: 20, y: 210, width: 380, height: 24))
    let multiline = FixtureTextView(frame: NSRect(x: 20, y: 70, width: 380, height: 120))
    let secure = NSSecureTextField(frame: NSRect(x: 20, y: 24, width: 380, height: 24))

    init(options: FixtureOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.editMenu()
        for field in [text, multiline] {
            field.mode = options.mode
            field.onChange = { [weak self] in self?.writeReport() }
            window.contentView?.addSubview(field)
        }
        text.singleLine = true
        text.setAccessibilityLabel("text")
        multiline.setAccessibilityLabel("multiline")
        secure.setAccessibilityLabel("secure")
        secure.delegate = self
        window.contentView?.addSubview(secure)
        window.title = "Insertion fixture: \(options.mode.rawValue)"
        window.center()
        window.makeKeyAndOrderFront(nil)
        let focused: NSView = ["multiline": multiline, "secure": secure][options.focus] ?? text
        window.isReleasedWhenClosed = false
        window.makeFirstResponder(focused)
        arm(focused)
        NSApp.activate()
        writeReport()
    }

    /// Sets up the focused field's mode that acts on the window rather than on an edit.
    private func arm(_ focused: NSView) {
        guard let field = focused as? FixtureTextView else { return }
        switch options.mode {
        case .stealsFocus:
            let other = field === text ? multiline : text
            field.onFirstSelectionRead = { [weak self] in self?.window.makeFirstResponder(other) }
        case .closesWindow:
            field.onFirstSelectionRead = { [weak self] in self?.window.close() }
        case .marksText:
            let marked = FixtureMode.markedText
            field.setMarkedText(
                marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0))
        default: break
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        writeReport()
    }

    /// Writes all three fields at once, atomically, so a reader never sees half a report.
    private func writeReport() {
        let fields = ["text": text.string, "multiline": multiline.string, "secure": secure.stringValue]
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else {
            return
        }
        try? data.write(to: options.report, options: .atomic)
    }

    /// Paste reaches a text view only as a menu key equivalent, so the fixture carries the standard Edit menu.
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        main.addItem(NSMenuItem(title: "Fixture", action: nil, keyEquivalent: ""))
        main.addItem(item)
        return main
    }
}

let fixture = Fixture(options: FixtureOptions(Array(CommandLine.arguments.dropFirst())))
let application = NSApplication.shared
application.setActivationPolicy(.regular)
application.delegate = fixture
application.run()
