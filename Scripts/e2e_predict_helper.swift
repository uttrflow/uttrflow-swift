import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

// The hands and eyes of Scripts/e2e_predict.sh: posts keys, reads the focused field, lists windows.
//
//   helper now                       epoch seconds with milliseconds
//   helper front                     bundle identifier of the frontmost application
//   helper windows <pid>             one on-screen window per line: number layer x y w h
//   helper read <bundle-id> [field]  JSON: role, value, caret, line (caret's line up to the caret); or one field raw
//   helper type <ms-per-char> <text> types text as unicode key events, one character at a time
//   helper key <keycode> [cmd] [ctrl] [opt] [shift]   presses one key with modifiers

/// Prints and exits, so every failure is one line on stderr and a non-zero status.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// One attribute of an accessibility element, or nil where the element does not answer.
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

/// The caret's offset in UTF-16 units, read from the selected range.
func caret(of element: AXUIElement) -> Int? {
    guard let raw = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
    var range = CFRange()
    // A CFTypeRef read from the accessibility API is an AXValue when the attribute is a range.
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range) else { return nil }
    return Int(range.location)
}

/// The caret's line up to the caret, which is what the suggestion loop calls the typed text.
func line(of value: String, endingAt offset: Int) -> String {
    let units = Array(value.utf16)
    let end = min(max(offset, 0), units.count)
    var start = end
    while start > 0, units[start - 1] != 0x0A { start -= 1 }
    return String(decoding: units[start..<end], as: UTF16.self)
}

/// The focused field of one application, read the way the app under test reads it; JSON, or one field raw.
func read(bundle: String, field: String?) {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
    else { fail("\(bundle) is not running") }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    guard let focused = attribute(root, kAXFocusedUIElementAttribute) else { fail("no focused element") }
    let element = unsafeBitCast(focused, to: AXUIElement.self)
    let value = (attribute(element, kAXValueAttribute) as? String) ?? ""
    let offset = caret(of: element) ?? value.utf16.count
    let json: [String: Any] = [
        "role": (attribute(element, kAXRoleAttribute) as? String) ?? "",
        "value": value,
        "caret": offset,
        "length": value.utf16.count,
        "line": line(of: value, endingAt: offset),
    ]
    if let field {
        guard let raw = json[field] else { fail("no field \(field)") }
        print(raw)
        return
    }
    let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    print(String(decoding: data ?? Data(), as: UTF8.self))
}

/// Every on-screen window one process owns, so a ghost panel shows up as a window that was not there before.
func windows(pid: pid_t) {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    for window in list where (window[kCGWindowOwnerPID as String] as? pid_t) == pid {
        let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
        let number = window[kCGWindowNumber as String] as? Int ?? 0
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        print(
            number, layer, Int(bounds["X"] ?? 0), Int(bounds["Y"] ?? 0), Int(bounds["Width"] ?? 0),
            Int(bounds["Height"] ?? 0))
    }
}

/// The modifier keys, so a modified press can hold and release them like a keyboard does.
let modifierKeys: [(flag: CGEventFlags, code: CGKeyCode)] = [
    (.maskCommand, 55), (.maskShift, 56), (.maskAlternate, 58), (.maskControl, 59),
]

/// Posts one key event with exactly these flags, never the flags the shared HID state happens to hold.
func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, units: [UniChar] = [], source: CGEventSource) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
    else { fail("could not build a key event") }
    event.flags = flags
    if !units.isEmpty {
        var units = units
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
    }
    event.post(tap: .cghidEventTap)
    usleep(4_000)
}

/// Holds the modifiers, presses the key, releases the modifiers, so nothing is left held afterwards.
func press(key code: CGKeyCode, flags: CGEventFlags, units: [UniChar] = [], source: CGEventSource) {
    let held = modifierKeys.filter { flags.contains($0.flag) }
    var current = CGEventFlags()
    for modifier in held {
        current.insert(modifier.flag)
        post(modifier.code, down: true, flags: current, source: source)
    }
    post(code, down: true, flags: current, units: units, source: source)
    post(code, down: false, flags: current, units: units, source: source)
    for modifier in held.reversed() {
        current.remove(modifier.flag)
        post(modifier.code, down: false, flags: current, source: source)
    }
}

/// Every character the current keyboard layout produces unshifted or shifted, mapped to its key; Terminal drops keys without one.
let layoutKeys: [Character: (code: CGKeyCode, shift: Bool)] = {
    var keys: [Character: (code: CGKeyCode, shift: Bool)] = [:]
    guard let input = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
        let raw = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData)
    else { return keys }
    let data = unsafeBitCast(raw, to: CFData.self) as Data
    data.withUnsafeBytes { bytes in
        guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
        for (shift, modifiers) in [(false, UInt32(0)), (true, UInt32(shiftKey >> 8) & 0xFF)] {
            for code in 0..<128 as Range<UInt16> {
                var deadKeys: UInt32 = 0
                var length = 0
                var units = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &units)
                guard status == noErr, length == 1, let scalar = Unicode.Scalar(units[0]) else { continue }
                let character = Character(scalar)
                if keys[character] == nil { keys[character] = (CGKeyCode(code), shift) }
            }
        }
    }
    return keys
}()

/// Types one character on its own key where the layout has one, and as a bare unicode event otherwise.
func type(_ character: Character, source: CGEventSource) {
    let key = layoutKeys[character]
    press(
        key: key?.code ?? 0, flags: key?.shift == true ? .maskShift : [], units: Array(character.utf16),
        source: source)
}

/// The modifier flags named on the command line.
func flags(from names: ArraySlice<String>) -> CGEventFlags {
    names.reduce(into: CGEventFlags()) { flags, name in
        switch name {
        case "cmd": flags.insert(.maskCommand)
        case "ctrl": flags.insert(.maskControl)
        case "opt": flags.insert(.maskAlternate)
        case "shift": flags.insert(.maskShift)
        default: fail("unknown modifier \(name)")
        }
    }
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else { fail("usage: helper now|front|windows|read|type|key ...") }
let rest = arguments.dropFirst()
guard let source = CGEventSource(stateID: .hidSystemState) else { fail("no HID event source") }

switch command {
case "now":
    print(String(format: "%.3f", Date().timeIntervalSince1970))
case "front":
    print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
case "windows":
    guard let pid = rest.first.flatMap({ pid_t($0) }) else { fail("windows <pid>") }
    windows(pid: pid)
case "read":
    guard let bundle = rest.first else { fail("read <bundle-id> [line|value|role|caret]") }
    read(bundle: bundle, field: rest.dropFirst().first)
case "type":
    guard rest.count == 2, let millis = UInt32(rest[rest.startIndex]) else { fail("type <ms> <text>") }
    for character in rest[rest.startIndex + 1] {
        type(character, source: source)
        usleep(millis * 1_000)
    }
case "key":
    guard let code = rest.first.flatMap({ CGKeyCode($0) }) else { fail("key <keycode> [cmd|ctrl|opt|shift]") }
    press(key: code, flags: flags(from: rest.dropFirst()), source: source)
default:
    fail("unknown command \(command)")
}
