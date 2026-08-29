import ApplicationServices
import AppKit
import CoreGraphics

// End-to-end test of Uttrflow's own interface, driven through the Accessibility API.
//
// Not screenshots. A screenshot proves a page was drawn; this presses a control and then
// asks the interface what changed, which is the only way to tell a button that works from
// a button that draws correctly and does nothing — the failure this whole product has
// repeatedly had.

// MARK: - Accessibility

func attr(_ e: AXUIElement, _ a: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success else { return nil }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}
func kids(_ e: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success,
        let l = v as? [AXUIElement]
    else { return [] }
    return l
}
func role(_ e: AXUIElement) -> String { attr(e, kAXRoleAttribute as String) ?? "?" }
func label(_ e: AXUIElement) -> String {
    [attr(e, kAXTitleAttribute as String), attr(e, kAXDescriptionAttribute as String),
     attr(e, kAXValueAttribute as String)]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ¦ ")
}
func actions(_ e: AXUIElement) -> [String] {
    var a: CFArray?
    AXUIElementCopyActionNames(e, &a)
    return (a as? [String]) ?? []
}

/// Brings Uttrflow to the front, and waits until macOS agrees that it is.
///
/// Synthetic key events go to whichever application is frontmost, not to whichever
/// element holds accessibility focus. Without this the keystrokes land in whatever
/// happens to be in front — a terminal, most likely — while the test cheerfully reports
/// that it typed, because setting focus succeeded and posting the events succeeded. Only
/// the words went somewhere else entirely.
@discardableResult
func bringToFront() -> Bool {
    guard let app = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == "com.uttrflow.Uttrflow" })
    else { return false }
    if app.isActive { return true }
    app.activate()
    for _ in 0..<20 {
        if app.isActive { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return app.isActive
}

/// Found once and kept.
///
/// Looked up afresh every time before, which meant a single transient miss from
/// `NSWorkspace` — it happens — killed a run three rounds in with no explanation. The
/// process does not change while a run is going; if it dies, the checks will say so on
/// their own terms rather than the harness vanishing.
let appElement: AXUIElement = {
    guard let p = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == "com.uttrflow.Uttrflow" })
    else {
        FileHandle.standardError.write(
            "uttrflow is not running. Build it with 'make app' and open it.\n".data(using: .utf8)!)
        exit(2)
    }
    let e = AXUIElementCreateApplication(p.processIdentifier)
    _ = AXUIElementSetMessagingTimeout(e, 5)
    return e
}()

/// Every element the app publishes, main window and menu bar alike.
func everything() -> [AXUIElement] {
    var out: [AXUIElement] = []
    func walk(_ e: AXUIElement, _ d: Int) {
        out.append(e)
        guard d < 24 else { return }
        for c in kids(e) { walk(c, d + 1) }
    }
    var v: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &v) == .success,
        let ws = v as? [AXUIElement] { for w in ws { walk(w, 0) } }
    if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &v) == .success,
        let bar = v as! AXUIElement? { walk(bar, 0) }
    return out
}

func labels() -> [String] { everything().map(label).filter { !$0.isEmpty } }
func says(_ needle: String) -> Bool {
    labels().contains { $0.localizedCaseInsensitiveContains(needle) }
}

@discardableResult
func tap(_ needle: String, exact: Bool = false) -> Bool {
    for e in everything() {
        let l = label(e)
        let hit = exact
            ? l.compare(needle, options: .caseInsensitive) == .orderedSame
            : l.localizedCaseInsensitiveContains(needle)
        guard hit, actions(e).contains(kAXPressAction as String) else { continue }
        return AXUIElementPerformAction(e, kAXPressAction as CFString) == .success
    }
    return false
}

/// Types into the nth text field on screen, with real keystrokes.
///
/// **Not** `AXUIElementSetAttributeValue(kAXValue)`. That writes the text into the
/// accessibility layer and SwiftUI's binding never hears about it: the field *displays*
/// what you set and the app receives nothing, so every assertion about what typing did
/// passes while nothing has been typed. Found by watching a search that filtered no rows.
@discardableResult
func typeInto(_ index: Int, _ text: String) -> Bool {
    let fields = everything().filter { role($0) == "AXTextField" || role($0) == "AXTextArea" }
    guard index < fields.count else { return false }
    let field = fields[index]
    bringToFront()
    guard AXUIElementSetAttributeValue(
        field, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success
    else { return false }
    settle(0.15)
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
    for character in text.utf16 {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown)
            else { return false }
            var unit = character
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            event.post(tap: .cghidEventTap)
        }
        settle(0.012)
    }
    settle(0.25)
    return true
}

/// Types into the first field that comes after a given label.
///
/// By label and not by index, because index 0 is the toolbar's *search* box on every page
/// that has one. Typing the word into the search box and then asserting the word is on
/// screen passes every time — the search box is on screen, with the word in it. Two
/// checks here were green that way before this existed.
@discardableResult
func typeAfter(_ labelText: String, _ text: String) -> Bool {
    let flat = everything()
    guard let start = flat.firstIndex(where: { label($0).localizedCaseInsensitiveContains(labelText) })
    else { return false }
    guard let field = flat[start...].first(where: { role($0) == "AXTextField" || role($0) == "AXTextArea" })
    else { return false }
    bringToFront()
    guard AXUIElementSetAttributeValue(
        field, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success
    else { return false }
    settle(0.15)
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
    for character in text.utf16 {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown)
            else { return false }
            var unit = character
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            event.post(tap: .cghidEventTap)
        }
        settle(0.012)
    }
    settle(0.3)
    return true
}

/// Where an element is on screen, in Quartz coordinates.
func centre(of e: AXUIElement) -> CGPoint? {
    var pv: CFTypeRef?
    var sv: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &pv) == .success,
        AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sv) == .success
    else { return nil }
    var origin = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &origin)
    AXValueGetValue(sv as! AXValue, .cgSize, &size)
    guard size.width > 0, size.height > 0 else { return nil }
    return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
}

/// Puts the pointer over the first element whose label matches, and leaves it there.
///
/// Row controls — Copy, Insert Again, Flag, Delete, Edit — are revealed on hover, and a
/// view at `opacity(0)` is hidden from the accessibility tree, so they simply are not
/// there to press until the pointer is over the row. Hovering is what a mouse user does,
/// so it is what the test does.
@discardableResult
func hover(_ needle: String) -> Bool {
    guard let target = everything().first(where: {
        label($0).localizedCaseInsensitiveContains(needle) && centre(of: $0) != nil
    }), let point = centre(of: target) else { return false }
    guard let source = CGEventSource(stateID: .hidSystemState),
        let move = CGEvent(
            mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point,
            mouseButton: .left)
    else { return false }
    move.post(tap: .cghidEventTap)
    settle(0.45)
    return true
}

/// Whether the interface says this anywhere that is *not* a text field.
///
/// The distinction matters for the same reason `typeAfter` exists: a word sitting in the
/// box you typed it into is not the word appearing in a list.
func showsOutsideAField(_ needle: String) -> Bool {
    everything().contains {
        role($0) != "AXTextField" && role($0) != "AXTextArea"
            && label($0).localizedCaseInsensitiveContains(needle)
    }
}

/// Empties whichever search box the page on screen has, so one test cannot filter the next.
func clearSearch() {
    guard let field = everything().first(where: { role($0) == "AXTextField" }) else { return }
    bringToFront()
    _ = AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, true as CFTypeRef)
    settle(0.1)
    guard let source = CGEventSource(stateID: .hidSystemState) else { return }
    // Select all, then delete: clearing by setting the value would not reach the app.
    let strokes: [(CGKeyCode, CGEventFlags)] = [(0, .maskCommand), (51, [])]
    for (key, flags) in strokes {
        for isDown in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }
    settle(0.3)
}

/// What a field currently holds, as the interface reports it.
func fieldValue(_ index: Int) -> String {
    let fields = everything().filter { role($0) == "AXTextField" || role($0) == "AXTextArea" }
    guard index < fields.count else { return "" }
    return attr(fields[index], kAXValueAttribute as String) ?? ""
}

func settle(_ seconds: Double = 0.35) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// Waits for a condition, because every button hands off to a store behind an actor.
@discardableResult
func waitFor(_ what: String, _ condition: () -> Bool, limit: Double = 4) -> Bool {
    let deadline = Date().addingTimeInterval(limit)
    while Date() < deadline {
        if condition() { return true }
        settle(0.1)
    }
    return condition()
}

// MARK: - Reporting

var failures: [String] = []
var checks = 0

func check(_ what: String, _ passed: Bool) {
    checks += 1
    if passed {
        print("  ✓ \(what)")
    } else {
        print("  ✗ \(what)")
        failures.append(what)
    }
}

func section(_ name: String) { print("\n— \(name)") }

// MARK: - The tests

func openMainWindow() {
    bringToFront()
    if !says("Hold ⌥") && !says("Dictionary") { tap("Open Uttrflow") }
    settle(0.6)
    if !says("Dictionary") { tap("Open Uttrflow"); settle(0.8) }
}

func go(_ page: String) -> Bool {
    let moved = tap(page, exact: true)
    settle(0.4)
    return moved
}

let pages = [
    "Dictation", "History", "Dictionary", "Corrections", "Insights", "Snippets",
    "Style", "Diagnostics", "Account",
]

func testNavigation(round: Int) {
    section("Navigation (round \(round))")
    for page in pages {
        let moved = go(page)
        // The page's own name is drawn as the toolbar title, so arriving is observable.
        check("\(page) opens", moved && waitFor(page, { says(page) }))
    }
}

/// Removes anything an earlier round left behind on the page in front.
///
/// A round that fails to clean up must not make the next one fail too: a second row with
/// a similar name makes `hover` ambiguous, and the failures that follow are about the
/// leftovers rather than about the product.
func sweepLeftovers(matching prefix: String) {
    for _ in 0..<6 {
        guard showsOutsideAField(prefix), hover(prefix), tap("Delete") else { return }
        settle(0.5)
    }
}

func testDictionary(round: Int) {
    section("Dictionary (round \(round))")
    _ = go("Dictionary")
    sweepLeftovers(matching: "Zyxwv\(nonce)")
    let word = "Zyxwv\(nonce)r\(round)"

    clearSearch()
    check("Add Word is offered", says("Add Word"))
    check("Add Word opens an editor", tap("Add Word") && waitFor("editor", { says("Write it as") }))
    settle(0.3)
    check("the editor asks how it sounds", says("Say it like"))
    check("typing the word", typeAfter("Write it as", word))
    settle(0.4)
    check("Save appears", says("Save"))
    tap("Save", exact: true)
    check("the word is listed", waitFor("row", { showsOutsideAField(word) }))
    check("the editor closed once the word was in", waitFor("closed", { !says("Write it as") }))

    // And it survives a page change, which is what "kept" means.
    _ = go("Insights")
    _ = go("Dictionary")
    check("the word is still there after leaving the page",
        waitFor("row", { showsOutsideAField(word) }))

    // A word already there is refused, and says so rather than replacing it silently.
    tap("Add Word")
    settle(0.3)
    _ = typeAfter("Write it as", word)
    check("a duplicate is refused with a reason", waitFor("refusal", { says("already in your dictionary") }))
    tap("Cancel", exact: true)
    check("the editor is gone", waitFor("closed", { !says("Write it as") }))

    // Delete it again, so a hundred rounds do not leave a hundred words behind.
    check("hovering the row reveals Delete", hover(word) && says("Delete"))
    check("Delete removes the word",
        tap("Delete") && waitFor("gone", { !showsOutsideAField(word) }))
}

func testSnippets(round: Int) {
    section("Snippets (round \(round))")
    _ = go("Snippets")
    sweepLeftovers(matching: "zqtrigger \(nonce)")
    let trigger = "zqtrigger \(nonce) \(round)"

    clearSearch()
    check("New Snippet is offered", says("New Snippet"))
    check("it opens an editor", tap("New Snippet") && waitFor("editor", { says("When I say") }))
    settle(0.3)
    check("typing the trigger", typeAfter("When I say", trigger))
    // A trigger with no text cannot be saved, and the page says why rather than leaving a
    // button that looks live and does nothing.
    check("a snippet with no text says what is missing",
        waitFor("problem", { says("needs something to type") }))

    check("typing the expansion", typeAfter("Type this", "Flat 402"))
    check("the problem clears once it can be saved",
        waitFor("clear", { !says("needs something to type") }))
    tap("Save", exact: true)
    check("the snippet is listed", waitFor("row", { showsOutsideAField(trigger) }))
    check("the editor closed", waitFor("closed", { !says("When I say") }))

    check("hovering the row reveals its controls", hover(trigger) && says("Delete"))
    check("Delete removes the snippet",
        tap("Delete") && waitFor("gone", { !showsOutsideAField(trigger) }))
}

/// Each page keeps its own search, and typing in one does not filter another.
///
/// Driven from Dictionary rather than History, and the difference is the point: a page's
/// search field appears only once there is something to search, and the only list this
/// harness can fill is the dictionary — it can add a word, where it cannot make somebody
/// dictate. Run against History on a machine with no dictations yet, this suite reported
/// a missing search field as a failure of the app, which it was not.
func testSearchIsPerPage(round: Int) {
    section("Search does not follow you between pages (round \(round))")
    let word = "Qsearch\(nonce)r\(round)"
    _ = go("Dictionary")
    sweepLeftovers(matching: "Qsearch\(nonce)")

    // Seeded, so the field exists whatever this Mac had in it before the run.
    tap("Add Word")
    settle(0.3)
    _ = typeAfter("Write it as", word)
    settle(0.3)
    tap("Save", exact: true)
    check("a word to search for", waitFor("row", { showsOutsideAField(word) }))

    let fields = everything().filter { role($0) == "AXTextField" }
    guard !fields.isEmpty else { check("Dictionary has a search field", false); return }
    check("Dictionary has a search field", true)
    clearSearch()
    check("typing a search reaches the app", typeInto(0, "zzzznomatch"))
    // The app received it only if the list actually narrowed. A field that merely shows
    // the text proves nothing.
    check("the search filters the list", waitFor("gone", { !showsOutsideAField(word) }))

    _ = go("Snippets")
    settle(0.4)
    check("the query did not follow to Snippets", !says("zzzznomatch"))
    check("the field on Snippets is empty", fieldValue(0) != "zzzznomatch")

    _ = go("Dictionary")
    clearSearch()
    check("the word is there again once the search is cleared",
        waitFor("row", { showsOutsideAField(word) }))
    // Left as it was found.
    _ = hover(word)
    tap("Delete")
    _ = waitFor("gone", { !showsOutsideAField(word) })
}

func testAccount(round: Int) {
    section("Account (round \(round))")
    _ = go("Account")
    check("it says whether you are signed in", says("Not signed in") || says("Signed in"))
    check("it says why the network is needed at all", says("needs the network once"))
    check("it promises the account is identity only", says("identity and nothing more"))
    check("it offers the action that matches the state",
        says("Not signed in") ? says("Sign In") : says("Sign Out"))
}

func testStyle(round: Int) {
    section("Style (round \(round))")
    _ = go("Style")
    check("it shows one sentence tidied both ways", says("THE SAME SENTENCE, BOTH WAYS"))
    check("it shows what was actually said", says("You said"))
    check("it never says which engine tidied it",
        !says("Foundation") && !says("Apple Intelligence") && !says("MLX"))
}

func testDiagnostics(round: Int) {
    section("Diagnostics (round \(round))")
    _ = go("Diagnostics")
    check("it names the engines section", says("Engines"))
    // §16: the user must never learn which engine ran. Six test files enforce this on the
    // presenters; costing nothing to check on the running product, where a wrongly wired
    // page would show it for real.
    for name in ["WhisperKit", "Whisper", "OpenAI", "MLX", "Llama", "Apple Intelligence"] {
        check("it never names \(name)", !says(name))
    }
    check("Copy Diagnostics is offered", says("Copy Diagnostics"))
    check("Copy Diagnostics can be pressed", tap("Copy Diagnostics"))
}

func testCorrections(round: Int) {
    section("Corrections (round \(round))")
    _ = go("Corrections")
    check("it explains what it lists", says("Every word Uttrflow changed today"))
    // The chip and the caption are two sentences about one number and used to disagree —
    // the chip counted the whole retained history under the word "today".
    if says("dictations today") || says("dictation today") {
        check("an empty page reads as the good outcome", says("good outcome"))
    }
}

func testInsights(round: Int) {
    section("Insights (round \(round))")
    _ = go("Insights")
    check("it says what it is measuring over", says("Last 90 days") || says("days"))
    // The rule the whole page is built on: nothing appears without something behind it.
    check("it never offers a time-saved figure", !says("time saved") || says("no “time saved”"))
}

func testSettingsWindow(round: Int) {
    section("Settings window (round \(round))")
    tap("Settings…")
    check("the Settings window opens", waitFor("open", { says("Languages") }))
    settle(0.4)

    for tab in ["General", "Languages", "Dictation", "Privacy"] {
        check("the \(tab) tab opens", tap(tab, exact: true))
        settle(0.35)
    }
    _ = tap("General", exact: true)
    settle(0.4)

    // Every switch must say what it switches. They were all anonymous once — "checkbox,
    // checked" and nothing more — because the label handed to the control was empty.
    let switches = everything().filter { role($0) == "AXCheckBox" }
    check("General has switches", !switches.isEmpty)
    check("every switch has a name",
        switches.allSatisfy { !(attr($0, kAXTitleAttribute as String) ?? "").isEmpty
            || !(attr($0, kAXDescriptionAttribute as String) ?? "").isEmpty })

    // And flipping one has to reach the app, not merely the control.
    let named = "floating button"
    if let before = switches.first(where: { label($0).localizedCaseInsensitiveContains(named) })
        .flatMap({ attr($0, kAXValueAttribute as String) })
    {
        check("flipping a switch changes it", flip(named) && switchValue(named) != before)
        // Put it back: a hundred rounds must not leave somebody's settings rearranged.
        _ = flip(named)
        check("flipping it back restores it", switchValue(named) == before)
    } else {
        check("the floating-button switch is there", false)
    }

    // Shut it by its close button, not by a label. Leaving it open is not untidiness: the
    // Settings window has a *Dictation* tab and the main window has a *Dictation* sidebar
    // button, so the next round's navigation would press whichever came first.
    check("the Settings window closes", closeWindow(titled: "Settings"))
    check("the main window is back in front", waitFor("main", { !says("Languages") }))
}

/// Presses a named switch, and says whether it could.
@discardableResult
func flip(_ named: String) -> Bool {
    guard let control = everything().first(where: {
        role($0) == "AXCheckBox" && label($0).localizedCaseInsensitiveContains(named)
    }) else { return false }
    bringToFront()
    let done = AXUIElementPerformAction(control, kAXPressAction as CFString) == .success
    settle(0.6)
    return done
}

func switchValue(_ named: String) -> String? {
    everything().first {
        role($0) == "AXCheckBox" && label($0).localizedCaseInsensitiveContains(named)
    }.flatMap { attr($0, kAXValueAttribute as String) }
}

/// Presses a window's close button, found by its subrole — it has no title to match on.
@discardableResult
func closeWindow(titled title: String) -> Bool {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &v) == .success,
        let windows = v as? [AXUIElement]
    else { return false }
    for window in windows {
        guard (attr(window, kAXTitleAttribute as String) ?? "")
            .localizedCaseInsensitiveContains(title) else { continue }
        guard let close = kids(window).first(where: {
            (attr($0, kAXSubroleAttribute as String) ?? "") == "AXCloseButton"
        }) else { continue }
        let done = AXUIElementPerformAction(close, kAXPressAction as CFString) == .success
        settle(0.6)
        return done
    }
    return false
}

func testMenuBar(round: Int) {
    section("Menu bar (round \(round))")
    check("the menu bar item is published", says("Uttrflow"))
    check("Start Dictation is offered", labels().contains { $0.contains("Start Dictation") })
    check("Settings is offered", labels().contains { $0.contains("Settings") })
}

// MARK: - Is there a screen to drive?

/// Refuses to run against a locked or sleeping Mac, and says so.
///
/// Worth more than it looks. With the screen locked, macOS composites no windows and the
/// accessibility tree degenerates — `AXWindows` answers with the application element
/// itself, whose children include itself, so any walk of it recurses until it looks
/// exactly like the app has hung. An hour went into that once: the app was blamed, then
/// the harness, then a commit was bisected, and all the while the machine was simply
/// showing its lock screen. A screenshot would have answered it in ten seconds.
/// The floating panels are windows of this app too, and their fields come first in the
/// accessibility tree. A clipboard picker left open behind a run puts *its* search box
/// at index zero, so a page's own search test types into it, watches nothing filter, and
/// blames the page — which is exactly the hour this cost once already.
///
/// Sent Escape rather than reported, because a stray panel is not a failure of the app:
/// it is a window somebody left open, and closing it is what a person would do first.
func dismissStrayPanels() {
    for _ in 0..<3 {
        guard strayPanel() != nil else { return }
        bringToFront()
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for isDown in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: isDown)?
                .post(tap: .cghidEventTap)
        }
        settle(0.4)
    }
}

/// Any window of this app that is neither the main window nor Settings: the floating
/// button, the clipboard picker, onboarding.
func strayPanel() -> AXUIElement? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &v) == .success,
        let windows = v as? [AXUIElement]
    else { return nil }
    return windows.first { window in
        let title = attr(window, kAXTitleAttribute as String) ?? ""
        guard !title.localizedCaseInsensitiveContains("Settings") else { return false }
        guard title != "Uttrflow" else { return false }
        // The floating button has no fields to steal focus with, and it is always there.
        let size = everything(in: window).count
        return size > 3
    }
}

/// Everything under one window, for the checks that must not see another.
func everything(in window: AXUIElement) -> [AXUIElement] {
    var out: [AXUIElement] = []
    func walk(_ e: AXUIElement, _ d: Int) {
        out.append(e)
        guard d < 24 else { return }
        for c in kids(e) { walk(c, d + 1) }
    }
    walk(window, 0)
    return out
}

func screenIsUsable() -> String? {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
        return "no window session — is this running over SSH, or as a daemon?"
    }
    if session["CGSSessionScreenIsLocked"] as? Int == 1 {
        return "the Mac is locked. Unlock it and run this again."
    }
    if session["kCGSSessionOnConsoleKey"] as? Bool == false {
        return "this session is not the one on screen. Switch to it and run this again."
    }
    return nil
}

// MARK: - Run

let rounds = Int(CommandLine.arguments.dropFirst().first ?? "1") ?? 1
/// Distinct per run, so one run's leftovers cannot be mistaken for this run's work — and
/// so a word this run adds is genuinely new, rather than meeting the store's refusal of a
/// duplicate left behind last time.
let nonce = String(Int(Date().timeIntervalSince1970) % 100_000)
if let reason = screenIsUsable() {
    print("cannot drive the interface: \(reason)")
    exit(3)
}
dismissStrayPanels()

openMainWindow()
guard says("Dictation") || says("Dictionary") else {
    print("""
        could not open the main window. If this is unexpected, take a screenshot before \
        assuming the app is at fault — a locked or sleeping display looks identical to a \
        hung one from here.
        """)
    exit(2)
}

for round in 1...rounds {
    testNavigation(round: round)
    testDictionary(round: round)
    testSnippets(round: round)
    testSearchIsPerPage(round: round)
    testCorrections(round: round)
    testInsights(round: round)
    testAccount(round: round)
    testStyle(round: round)
    testDiagnostics(round: round)
    testSettingsWindow(round: round)
    testMenuBar(round: round)
}

print("\n\(checks - failures.count)/\(checks) checks passed")
if !failures.isEmpty {
    print("\nFAILED:")
    for f in failures { print("  • \(f)") }
    exit(1)
}
