import AppKit
import ApplicationServices
import CoreText
import Foundation
import UttrflowPredict

private import Synchronization

@_silgen_name("_AXUIElementGetWindow")
private func axUIElementGetWindow(
    _ element: AXUIElement, _ windowNumber: UnsafeMutablePointer<CGWindowID>
) -> AXError

/// The frontmost application's identity, taken on the main thread where `NSWorkspace` is safe to read.
public struct FrontmostApp: Sendable {
    /// Addresses the app for the Accessibility read.
    public let processIdentifier: Int32
    /// The app's bundle identifier, which every capability table is keyed by.
    public let bundleIdentifier: String
    /// The app as the user knows it, cleaned of the marks some applications pad it with.
    public let name: String

    public init(processIdentifier: Int32, bundleIdentifier: String, name: String) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// Reads the focused field once, for everything the suggestion loop needs. See `Docs/predict.md`.
public enum FocusedFieldReader {
    /// Its own thread, because these calls block until the other application answers.
    private static let queue = LatestOnlyQueue(label: "com.uttrflow.focused-field", qos: .userInitiated)

    /// Keeps armed-offer checks from replacing a full field read.
    private static let selectionQueue = LatestOnlyQueue(
        label: "com.uttrflow.focused-selection", qos: .utility)

    /// Holds the stable answers for one focused field and window only.
    private static let stableSnapshot = OneEntryCache<StableSnapshotKey, StableSnapshotValue>()

    /// The process, field and window that give cached answers their identity.
    private struct StableSnapshotKey: @unchecked Sendable, Equatable {
        let processIdentifier: Int32
        let field: AXUIElement
        let window: AXUIElement?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.processIdentifier == rhs.processIdentifier && CFEqual(lhs.field, rhs.field)
                && sameWindow(lhs.window, rhs.window)
        }
    }

    /// Stable Accessibility answers, retained only for one focused field and window.
    private struct StableSnapshotValue: @unchecked Sendable {
        let identity: FieldNames
        let document: String?
        let fieldFrame: CGRect?
        let windowFrame: CGRect?
        let windowTitle: String?
    }

    /// The primary screen's top edge, cached because `NSScreen` is main-thread-only and this reads off it.
    private static let cachedPrimaryScreenMaxY = Mutex<CGFloat>(0)

    /// Whether the caches are already being kept up to date, so preparing twice observes once.
    @MainActor private static var prepared = false

    /// Fills the caches the off-main read depends on and keeps them filled. See `Docs/predict-ime.md`.
    @MainActor
    public static func prepare() {
        guard !prepared else { return }
        prepared = true
        CompositionProbe.startObservingInputSource()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { refreshPrimaryScreenMaxY() } }
        }
        refreshPrimaryScreenMaxY()
    }

    /// Asks AppKit where the primary screen ends, the one place in the read path that touches `NSScreen`.
    @MainActor
    private static func refreshPrimaryScreenMaxY() {
        let maxY = NSScreen.screens.first?.frame.maxY ?? 0
        cachedPrimaryScreenMaxY.withLock { $0 = maxY }
    }

    /// The frontmost application's identity, or `nil` when it is Uttrflow, whose AX tree must not be walked off the main actor.
    @MainActor
    public static func frontmostApp() -> FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = app.bundleIdentifier,
            bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }
        // Some applications pad their name with control and direction marks, which would reach the model verbatim.
        let name = SurroundingsText.cleaned(app.localizedName ?? bundleIdentifier)
            .trimmingCharacters(in: .whitespaces)
        return FrontmostApp(
            processIdentifier: app.processIdentifier, bundleIdentifier: bundleIdentifier,
            name: name.isEmpty ? bundleIdentifier : name)
    }

    /// One reading, off the main thread, or `nil` when nothing usable is focused.
    public static func read() async -> FocusedFieldSnapshot? {
        let fullTreeGeneration = fullTree.generation
        // Identity is taken on the main actor first, because the blocking read below may not touch `NSWorkspace`.
        guard let app = await frontmostApp() else { return nil }
        // A field that stops answering costs the turn half a second at most, and no later turn waits behind it.
        return await queue.run(within: .milliseconds(500)) { isWanted in
            let reading = snapshot(app: app, while: isWanted)
            // A browser engine answers zero-size caret bounds until its full tree is on.
            if FullTreeSwitch.isNeeded(in: app.bundleIdentifier, after: reading) {
                fullTree.switchOn(
                    processIdentifier: app.processIdentifier, bundleIdentifier: app.bundleIdentifier,
                    host: fullTreeHost(app.processIdentifier), generation: fullTreeGeneration)
            }
            return reading
        }
    }

    /// Reads only the focused element and selection, for the short time a suggestion is armed.
    public static func focusedSelection() async -> FocusedFieldSelectionRead {
        guard let app = await frontmostApp() else { return .unavailable }
        let read: FocusedFieldSelectionRead? = await selectionQueue.run(within: .milliseconds(250)) {
            isWanted in
            guard isWanted(), AXIsProcessTrusted(),
                let field = SurfaceProbe.focusedField(of: app.processIdentifier), isWanted()
            else { return .unavailable }
            _ = AXUIElementSetMessagingTimeout(field, elementTimeoutInSeconds)
            guard let range = SurfaceProbe.selectedRange(field), isWanted() else { return .unavailable }
            return .selection(
                FocusedFieldSelection(
                    processIdentifier: app.processIdentifier, elementHash: CFHash(field),
                    range: NSRange(location: range.location, length: range.length)))
        }
        return read ?? .timedOut
    }

    /// Cancels a selection poll when the offer is withdrawn.
    public static func cancelFocusedSelectionRead() { selectionQueue.invalidate() }

    /// Stops the current field read after its in-flight message, so a canceled turn sends no further questions.
    public static func cancelRead() { queue.invalidate() }

    /// The full Accessibility trees the suggestion loop turned on, kept so stopping the loop turns them off.
    private static let fullTree = FullTreeSwitch()

    /// Turns off every browser engine's full tree the suggestion loop turned on.
    public static func releaseFullTrees(except processIdentifier: Int32? = nil) {
        fullTree.switchOffEverything(except: processIdentifier, host: fullTreeHost)
    }

    /// One application's full-tree switches, each message capped so a stalled application cannot hold the caller.
    private static func fullTreeHost(_ processIdentifier: Int32) -> FullTreeSwitch.Host {
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, elementTimeoutInSeconds)
        return FullTreeSwitch.Host(
            read: { attribute in
                var value: AnyObject?
                guard AXUIElementCopyAttributeValue(application, attribute as CFString, &value) == .success
                else { return nil }
                return (value as? NSNumber)?.boolValue
            },
            write: { attribute, isOn in
                AXUIElementSetAttributeValue(
                    application, attribute as CFString, isOn ? kCFBooleanTrue : kCFBooleanFalse) == .success
            })
    }

    /// Its own thread for the wider walk, so an application slow to describe its window never holds up a field read.
    private static let surroundingsQueue = LatestOnlyQueue(
        label: "com.uttrflow.surroundings", qos: .utility)

    /// How long one Accessibility call into another application may wait, since a stalled one would otherwise wait seconds.
    static let elementTimeoutInSeconds: Float = 0.05

    /// How long the turn waits for the wider walk before going on without it.
    private static let surroundingsAllowance = Duration.milliseconds(200)

    /// What is on screen around the focused field, or `nil` when nothing usable is focused or the wait ran out.
    public static func surroundings() async -> Surroundings? {
        guard let app = await frontmostApp() else { return nil }
        // A walk that does not answer in time is left to finish; a newer walk replaces one still queued.
        return await surroundingsQueue.run(within: surroundingsAllowance) { _ in surroundings(of: app) }
    }

    /// The same read synchronously, for an application front or not, which is what a probe shows the operator.
    public static func surroundings(of app: FrontmostApp) -> Surroundings? {
        // A field with no window, or a window focused as a whole, has nothing around it worth a walk.
        guard AXIsProcessTrusted(), !slowFields.isQuiet(app.processIdentifier),
            let field = SurfaceProbe.focusedField(of: app.processIdentifier),
            !slowFields.isResting(SlowFields.Key(process: app.processIdentifier, element: CFHash(field))),
            let window = element(field, kAXWindowAttribute), !CFEqual(field, window)
        else { return nil }
        let answers = AXNode(window).answers
        return Surroundings.collect(
            around: AXNode(field), in: AXElementTree(), windowTitle: answers.title, windowFrame: answers.frame
        )
    }

    /// The fields whose reads ran past their budget lately, which are left alone until their rest is over.
    static let slowFields = SlowFields()

    /// Lets an application quieted by a resting field be asked again, for a click, a switch or a key that may move focus.
    public static func focusMayHaveMoved() {
        slowFields.focusMayHaveMoved()
        stableSnapshot.clear()
    }

    /// The same reading, synchronously, for the queue above and for the capability probe; the identity is read on main.
    static func snapshot(
        app: FrontmostApp, while isWanted: @Sendable () -> Bool = { true }
    ) -> FocusedFieldSnapshot? {
        let started = DispatchTime.now().uptimeNanoseconds
        let budget = FieldReadBudget.start()
        // An application whose focused field rests is not even asked for its focus, which can itself be the slow part.
        guard AXIsProcessTrusted(), !slowFields.isQuiet(app.processIdentifier),
            let field = SurfaceProbe.focusedField(of: app.processIdentifier)
        else { return nil }
        let slow = SlowFields.Key(process: app.processIdentifier, element: CFHash(field))
        // A field whose read ran over lately is asked nothing, so a heavy document does not stall its application every turn.
        guard !slowFields.isResting(slow) else { return nil }
        // Every question to the field gives up quickly, so a field that stops answering costs a moment, not the loop.
        _ = AXUIElementSetMessagingTimeout(field, elementTimeoutInSeconds)
        var ranOver = false
        // Checked before every question after the first: a superseded read stops, and one past its budget stops and rests the field.
        let goOn: () -> Bool = {
            guard isWanted() else { return false }
            guard budget.isSpent else { return true }
            ranOver = true
            return false
        }
        let answer = read(field, of: app, started: started, while: goOn)
        if ranOver {
            slowFields.ranOver(slow)
        } else if answer != nil {
            slowFields.answered(slow)
        }
        return answer
    }

    /// Everything the snapshot holds, each question asked once and none after `goOn` says stop.
    private static func read(
        _ field: AXUIElement, of app: FrontmostApp, started: UInt64, while goOn: () -> Bool
    ) -> FocusedFieldSnapshot? {
        let window = element(field, kAXWindowAttribute)
        guard goOn() else { return nil }
        let cacheKey = StableSnapshotKey(
            processIdentifier: app.processIdentifier, field: field, window: window)
        let cached = stableSnapshot.value(for: cacheKey)
        let fieldIdentity = cached?.identity ?? SurfaceProbe.names(of: field)
        guard let role = fieldIdentity.role else { return nil }
        guard goOn() else { return nil }
        let stable: StableSnapshotValue
        if let cached {
            stable = cached
        } else {
            let fieldDocument = SurfaceProbe.string(field, kAXDocumentAttribute)
            guard goOn() else { return nil }
            let windowAnswers = window.map { AXNode($0).answers }
            let document = fieldDocument ?? windowAnswers?.document
            guard goOn() else { return nil }
            let fieldFrame = frame(of: field)
            guard goOn() else { return nil }
            let windowFrame = windowAnswers?.frame
            guard goOn() else { return nil }
            let windowTitle = windowAnswers?.title
            guard goOn() else { return nil }
            let value = StableSnapshotValue(
                identity: fieldIdentity, document: document, fieldFrame: fieldFrame,
                windowFrame: windowFrame, windowTitle: windowTitle)
            stableSnapshot.insert(value, for: cacheKey)
            stable = value
        }
        let identity = stable.identity
        // Decided before the value is fetched, so a declared secure field's contents are never read at all.
        let declaredSecure = identity.isDeclaredSecure
        guard goOn() else { return nil }
        let selected = SurfaceProbe.selection(field)
        if case .discontinuous = selected { return nil }
        let range: CFRange?
        if case .range(let value) = selected {
            range = value
        } else {
            range =
                declaredSecure || !goOn()
                ? nil
                : markerSelection(field).map {
                    CFRange(location: $0.range.location, length: $0.range.length)
                }
        }
        guard goOn() else { return nil }
        let read = SurfaceProbe.text(of: field, names: identity, at: range)
        let value = read.value
        let secure = read.isSecure
        guard goOn() else { return nil }
        // The attributed string carries the characters, so a secure field is never asked for its style.
        let styleRange = range.flatMap { boundedStyleRange($0) }
        let style = secure ? nil : styleRange.flatMap { typeStyle(field, at: $0) }
        guard goOn() else { return nil }
        let flipped = cachedPrimaryScreenMaxY.withLock { $0 }
        let marked = CompositionProbe.markedText(of: field)
        guard goOn() else { return nil }
        // A combobox field says when its own list is open, one flag on the field itself.
        let ownList = SurfaceProbe.integer(field, "AXExpanded") == 1
        guard goOn() else { return nil }
        let isEnabled = SurfaceProbe.boolean(field, kAXEnabledAttribute)
        guard goOn() else { return nil }
        let isEditable = SurfaceProbe.boolean(field, kAXIsEditableAttribute)
        guard goOn() else { return nil }
        let fieldRect = stable.fieldFrame
        let paragraphDirection: WritingDirection
        if let range, range.length == 0, range.location > 0,
            read.selection?.length == 0, read.selection?.location == value?.utf16.count,
            !secure, goOn(),
            let attributed = SurfaceProbe.parameterized(
                field, kAXAttributedStringForRangeParameterizedAttribute,
                CFRange(location: range.location - 1, length: 1)),
            CFGetTypeID(attributed) == CFAttributedStringGetTypeID()
        {
            paragraphDirection = Self.writingDirection(
                inAttributed: unsafeDowncast(attributed, to: CFAttributedString.self))
        } else {
            paragraphDirection = .unknown
        }
        let caretResult = caret(
            field, at: range, value: value, selection: read.selection, frame: fieldRect,
            pointSize: style?.size, paragraphDirection: paragraphDirection, while: goOn)
        guard goOn() else { return nil }
        let windowRect = stable.windowFrame
        let appPickerOpen =
            ownList
            || window.map {
                FocusedWindowPicker.isOpen(
                    in: AXNode($0), near: fieldRect, using: AXElementTree(), while: goOn)
            } ?? false
        guard goOn() else { return nil }
        let title = stable.windowTitle
        // An editor that draws its own text keeps an empty input at the caret, so its line is read off the rendered text.
        let hidden =
            secure ? nil : hiddenInputLine(field, role: role, value: value, frame: fieldRect, while: goOn)
        let number = windowNumber(while: goOn) { windowNumber(of: field) }
        guard goOn() else { return nil }

        return FocusedFieldSnapshot(
            bundleIdentifier: app.bundleIdentifier,
            applicationName: app.name,
            role: role,
            subrole: identity.subrole,
            identifier: identity.identifier,
            placeholder: identity.placeholder,
            accessibilityDescription: identity.description,
            document: stable.document,
            value: secure ? nil : hidden.map { $0.before + $0.after } ?? value,
            selection: hidden.map { NSRange(location: $0.before.utf16.count, length: 0) } ?? read.selection,
            focusedFieldIdentity: FocusedFieldIdentity(
                processIdentifier: app.processIdentifier, elementHash: CFHash(field)),
            caret: (hidden?.caret ?? caretResult?.caret).map { flip($0, below: flipped) },
            writingDirection: hidden == nil ? caretResult?.direction ?? .unknown : .unknown,
            window: windowRect.map { flip($0, below: flipped) },
            field: (hidden?.line ?? fieldRect).flatMap {
                FocusedFieldSnapshot.isCaretShaped($0) ? nil : flip($0, below: flipped)
            },
            pointSize: style?.size,
            fontFamily: style?.family,
            isBold: style?.isBold ?? false,
            isItalic: style?.isItalic ?? false,
            textColor: style?.color,
            isSecure: secure,
            isEnabled: isEnabled,
            isEditable: isEditable,
            isComposing: Composition.isComposing(
                markedText: marked, inputSource: CompositionProbe.inputSourceKind()),
            markedText: marked,
            showsOwnList: appPickerOpen,
            readMicroseconds: Int((DispatchTime.now().uptimeNanoseconds - started) / 1000),
            windowTitle: title,
            windowNumber: number
        )
    }

    /// Reads a window number only while this field snapshot is still wanted.
    static func windowNumber(while isWanted: () -> Bool, read: () -> UInt32?) -> UInt32? {
        guard isWanted() else { return nil }
        let number = read()
        guard isWanted() else { return nil }
        return number
    }

    /// The system window containing this field, which distinguishes same-app windows with identical AX fields.
    static func windowNumber(of field: AXUIElement) -> UInt32? {
        var number: CGWindowID = 0
        guard axUIElementGetWindow(field, &number) == .success else { return nil }
        return number
    }

    /// The caret's line read off an editor's rendered text, for the empty caret-sized input such an editor keeps focused.
    private static func hiddenInputLine(
        _ field: AXUIElement, role: String, value: String?, frame: CGRect?, while goOn: () -> Bool
    ) -> HiddenInputLine.Reading? {
        let probe = HiddenInputLine.probe(
            AXNode(field), role: role, value: value, frame: { frame }, in: AXElementTree(), while: goOn)
        guard case .line(let reading) = probe else { return nil }
        return reading
    }

    /// Whether both keys name the same window, including the absence of a window.
    private static func sameWindow(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (let lhs?, let rhs?): CFEqual(lhs, rhs)
        default: false
        }
    }

    /// Bounds an attributed style read at the start of a selection.
    private static func boundedStyleRange(_ range: CFRange) -> CFRange {
        CFRange(location: range.location, length: min(range.length, ValueWindow.selectionLimit))
    }

    /// Accessibility measures from the top of the primary screen; AppKit measures from the bottom.
    private static func flip(_ rect: CGRect, below primaryScreenMaxY: CGFloat) -> CGRect {
        SuggestionGeometry.fromAccessibility(rect, primaryScreenMaxY: primaryScreenMaxY)
    }

    /// An attribute that is an element, under the same short timeout the field itself answers under.
    private static func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        SurfaceProbe.element(owner, attribute, timeoutInSeconds: elementTimeoutInSeconds)
    }

    /// An element's rectangle as Accessibility reports it, or nothing when it gives no position or no size.
    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin: CGPoint = SurfaceProbe.value(element, kAXPositionAttribute, .cgPoint),
            let size: CGSize = SurfaceProbe.value(element, kAXSizeAttribute, .cgSize)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The caret's screen rectangle, from the selection where the field answers it and from the text marker where it does not; `frame` is the field's own, already read.
    private static func caret(
        _ field: AXUIElement, at range: CFRange?, value: String?, selection: NSRange?, frame: CGRect?,
        pointSize: CGFloat?, paragraphDirection: WritingDirection, while goOn: () -> Bool
    ) -> CaretLocator.Result? {
        CaretLocator.result(
            at: range.map { (location: $0.location, length: $0.length) }, frame: frame,
            pointSize: pointSize, value: value, textSelectionLocation: selection?.location,
            paragraphDirection: paragraphDirection,
            bounds: { goOn() ? SurfaceProbe.bounds(field, at: CFRange(location: $0, length: $1)) : nil },
            markerBounds: { goOn() ? markerBounds(field) : nil })
    }

    /// What a field says about its own type, either half of which it may leave out.
    struct TypeStyle: Sendable, Equatable {
        /// The type size in points, so the ghost matches the line it sits on.
        let size: CGFloat?
        /// The font family, so the ghost is set in the face the line is.
        let family: String?
        /// Whether the face is bold, so the ghost keeps the run's weight.
        let isBold: Bool
        /// Whether the face is italic or oblique, so the ghost keeps the run's slant.
        let isItalic: Bool
        /// The text colour, so the ghost reads against the field rather than against Uttrflow's appearance.
        var color: TextColor?
    }

    /// One element of another application, compared the way Accessibility compares them, its answers kept once asked.
    struct AXNode: Equatable {
        let element: AXUIElement
        let answers: Answers

        init(_ element: AXUIElement) {
            self.element = element
            answers = Answers(element)
            // Every question to this element gives up quickly, so a window that stops answering costs a moment, not the loop.
            _ = AXUIElementSetMessagingTimeout(element, elementTimeoutInSeconds)
        }

        /// The focused field as its caller already capped it, its messaging timeout left as it is.
        init(keepingTimeout element: AXUIElement) {
            self.element = element
            answers = Answers(element)
        }

        static func == (lhs: AXNode, rhs: AXNode) -> Bool { CFEqual(lhs.element, rhs.element) }
    }

    /// What the collector asks one element: its shape in a single message, and its value apart, only when its text is read.
    final class Answers {
        /// The attributes asked for together, in the order the answers come back, the value left out since it can be a whole document.
        static let attributes = [
            kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute,
            kAXDescriptionAttribute, kAXChildrenAttribute, kAXParentAttribute, kAXSubroleAttribute,
            kAXIdentifierAttribute, kAXPlaceholderValueAttribute, kAXHiddenAttribute,
            kAXDocumentAttribute,
        ]

        /// How many UTF-16 units of a long value are read from its end, twice the per-element cap so cleaning still leaves enough.
        static let valueReadLimit = Surroundings.maximumCharactersPerElement * 2

        private let element: AXUIElement
        private var fetched: [AnyObject]?
        private var valueRead: String??

        init(_ element: AXUIElement) {
            self.element = element
        }

        /// Answers already in hand, one per attribute, so a test can ask them without another application.
        init(_ element: AXUIElement, fetched: [AnyObject]) {
            self.element = element
            self.fetched = fetched.count == Self.attributes.count ? fetched : []
        }

        /// The answers, one per attribute, an element that does not answer at all standing as none.
        private var values: [AnyObject] {
            if let fetched { return fetched }
            var answers: CFArray?
            let result = AXUIElementCopyMultipleAttributeValues(
                element, Self.attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &answers)
            let values = result == .success ? (answers as? [AnyObject]) ?? [] : []
            fetched = values.count == Self.attributes.count ? values : []
            return fetched ?? []
        }

        /// One answer by attribute, or nothing when the element did not answer.
        private subscript(_ attribute: String) -> AnyObject? {
            Self.attributes.firstIndex(of: attribute).flatMap {
                values.indices.contains($0) ? values[$0] : nil
            }
        }

        var role: String? { self[kAXRoleAttribute] as? String }
        var subrole: String? { self[kAXSubroleAttribute] as? String }
        var title: String? { self[kAXTitleAttribute] as? String }
        var document: String? { self[kAXDocumentAttribute] as? String }

        /// Whether the element declares itself secure by role or subrole, or as a field by name, asked of the answers already fetched.
        var isSecure: Bool {
            SecureField.isDeclaredSecureOnScreen(
                role: role, subrole: self[kAXSubroleAttribute] as? String,
                identifier: self[kAXIdentifierAttribute] as? String,
                placeholder: self[kAXPlaceholderValueAttribute] as? String,
                description: self[kAXDescriptionAttribute] as? String)
        }

        /// What the element says: the end of its value, else its title, else its description, and nothing for a secure element.
        var text: String? {
            guard !isSecure else { return nil }
            let candidates: [() -> String?] = [
                { self.value }, { self[kAXTitleAttribute] as? String },
                { self[kAXDescriptionAttribute] as? String },
            ]
            for candidate in candidates {
                if let text = candidate(), text.contains(where: { !$0.isWhitespace }) { return text }
            }
            return nil
        }

        /// The element's value, read once and only its last ``valueReadLimit`` units when the element can say how long it is.
        private var value: String? {
            if let valueRead { return valueRead }
            let read = Self.tail(of: element)
            valueRead = .some(read)
            return read
        }

        /// The end of an element's value by range where it is long; unknown lengths and failed ranges are skipped.
        private static func tail(of element: AXUIElement) -> String? {
            var length: AnyObject?
            guard
                AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &length)
                    == .success, let count = (length as? NSNumber)?.intValue, count >= 0
            else { return nil }
            if count > valueReadLimit {
                let range = CFRange(location: count - valueReadLimit, length: valueReadLimit)
                guard
                    let tail = SurfaceProbe.parameterized(
                        element, kAXStringForRangeParameterizedAttribute, range)
                        as? String, tail.utf16.count == valueReadLimit
                else { return nil }
                return tail
            }
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success
            else {
                return nil
            }
            return value as? String
        }

        /// Where the element is, or nothing when it reports no position or no size.
        var frame: CGRect? {
            guard let origin: CGPoint = SurfaceProbe.unwrap(self[kAXPositionAttribute], .cgPoint),
                let size: CGSize = SurfaceProbe.unwrap(self[kAXSizeAttribute], .cgSize)
            else { return nil }
            return CGRect(origin: origin, size: size)
        }

        var children: [AXUIElement] { self[kAXChildrenAttribute] as? [AXUIElement] ?? [] }

        /// Whether a sibling list contains links, which identify other navigable conversations.
        var isConversationLinkList: Bool {
            guard role == "AXList" else { return false }
            return children.contains { child in
                let child = Answers(child)
                return child.role == "AXLink"
                    || child.children.contains { Answers($0).role == "AXLink" }
            }
        }

        var isHidden: Bool { (self[kAXHiddenAttribute] as? NSNumber)?.boolValue ?? false }

        var parent: AXUIElement? {
            guard let value = self[kAXParentAttribute], CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }
            // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
            return unsafeDowncast(value, to: AXUIElement.self)
        }
    }

    /// The other application's window as the surroundings collector walks it, one Accessibility message per element.
    struct AXElementTree: ElementTree {
        func role(of node: AXNode) -> String? { node.answers.role }
        func subrole(of node: AXNode) -> String? { node.answers.subrole }
        func isConversationLinkList(_ node: AXNode) -> Bool { node.answers.isConversationLinkList }
        func isHidden(_ node: AXNode) -> Bool { node.answers.isHidden }
        func isSecure(_ node: AXNode) -> Bool { node.answers.isSecure }
        func text(of node: AXNode) -> String? { node.answers.text }
        func frame(of node: AXNode) -> CGRect? { node.answers.frame }
        func children(of node: AXNode) -> [AXNode] { node.answers.children.map { AXNode($0) } }

        func attribute(_ name: String, of node: AXNode) -> FieldAnswer {
            Self.answer {
                var value: AnyObject?
                return (AXUIElementCopyAttributeValue(node.element, name as CFString, &value), value)
            }
        }

        func attribute(_ name: String, of node: AXNode, range: NSRange) -> FieldAnswer {
            var cfRange = CFRange(location: range.location, length: range.length)
            guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return .unsupported }
            return Self.answer {
                var value: AnyObject?
                let error = AXUIElementCopyParameterizedAttributeValue(
                    node.element, name as CFString, parameter, &value)
                return (error, value)
            }
        }

        func markerSelection(of node: AXNode) -> MarkerSelection? {
            FocusedFieldReader.markerSelection(node.element)
        }

        /// Asked in one message; an element that will not answer the batch is asked one attribute at a time.
        func attributes(_ names: [String], of node: AXNode) -> [FieldAnswer] {
            var answers: CFArray?
            let result = AXUIElementCopyMultipleAttributeValues(
                node.element, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &answers)
            guard result == .success, let values = answers as? [AnyObject], values.count == names.count else {
                return names.map { attribute($0, of: node) }
            }
            return values.map { .value($0) }
        }

        /// One message's outcome as a `FieldAnswer`, a failure at the element's timeout counted as timed out.
        private static func answer(_ send: () -> (AXError, AnyObject?)) -> FieldAnswer {
            let started = DispatchTime.now().uptimeNanoseconds
            let (error, value) = send()
            let elapsed = DispatchTime.now().uptimeNanoseconds - started
            return FieldAnswer.classify(
                code: error.rawValue, value: value, elapsedSeconds: Double(elapsed) / 1_000_000_000,
                timeoutSeconds: Double(elementTimeoutInSeconds))
        }

        /// The element's parent, stopping at the window so the walk never crosses into the application's other windows.
        func parent(of node: AXNode) -> AXNode? {
            guard node.answers.role != kAXWindowRole, let parent = node.answers.parent.map({ AXNode($0) }),
                parent.answers.role != kAXApplicationRole
            else { return nil }
            return parent
        }
    }

    /// The font at the caret, so the ghost is set in the field's own face and size.
    private static func typeStyle(_ field: AXUIElement, at range: CFRange) -> TypeStyle? {
        let widened = AccessibilityRange.widenedForStyle(range)
        guard
            let answer = SurfaceProbe.parameterized(
                field, kAXAttributedStringForRangeParameterizedAttribute, widened),
            CFGetTypeID(answer) == CFAttributedStringGetTypeID()
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        return typeStyle(inAttributed: unsafeDowncast(answer, to: CFAttributedString.self))
    }

    /// The font size in an attributed string, from whichever form the application answered in.
    static func pointSize(inAttributed attributed: CFAttributedString) -> CGFloat? {
        typeStyle(inAttributed: attributed)?.size
    }

    static func writingDirection(inAttributed attributed: CFAttributedString) -> WritingDirection {
        guard CFAttributedStringGetLength(attributed) > 0,
            let attribute = CFAttributedStringGetAttribute(
                attributed, 0, kCTParagraphStyleAttributeName, nil),
            CFGetTypeID(attribute) == CTParagraphStyleGetTypeID()
        else { return .unknown }
        let style = unsafeDowncast(attribute, to: CTParagraphStyle.self)
        var direction = CTWritingDirection.natural
        guard
            CTParagraphStyleGetValueForSpecifier(
                style, .baseWritingDirection, MemoryLayout<CTWritingDirection>.size, &direction)
        else { return .unknown }
        return switch direction {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        default: .unknown
        }
    }

    /// The font in an attributed string: a Core Text font where AppKit put one, else the `AXFont` dictionary most applications answer with.
    static func typeStyle(inAttributed attributed: CFAttributedString) -> TypeStyle? {
        guard CFAttributedStringGetLength(attributed) > 0 else { return nil }
        let color = textColor(inAttributed: attributed)
        if let font = CFAttributedStringGetAttribute(attributed, 0, kCTFontAttributeName, nil),
            CFGetTypeID(font) == CTFontGetTypeID()
        {
            // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
            let font = unsafeDowncast(font, to: CTFont.self)
            let traits = CTFontGetSymbolicTraits(font)
            return TypeStyle(
                size: CTFontGetSize(font), family: CTFontCopyFamilyName(font) as String,
                isBold: traits.contains(.traitBold), isItalic: traits.contains(.traitItalic), color: color)
        }
        var size: CGFloat?
        var family: String?
        var isBold = false
        var isItalic = false
        if let described = CFAttributedStringGetAttribute(attributed, 0, Self.axFontKey as CFString, nil),
            CFGetTypeID(described) == CFDictionaryGetTypeID()
        {
            // Checked by type ID above; a Core Foundation dictionary bridges to Foundation without AppKit.
            let font = unsafeDowncast(described, to: CFDictionary.self) as NSDictionary
            size = (font[Self.axFontSizeKey] as? NSNumber).map { CGFloat($0.doubleValue) }
            family = font[Self.axFontFamilyKey] as? String
            let name = font[Self.axFontNameKey] as? String
            let style = font[Self.axFontStyleKey] as? String
            let nameTraits = name.map {
                CTFontGetSymbolicTraits(CTFontCreateWithName($0 as CFString, size ?? 12, nil))
            }
            let styleName = style?.lowercased() ?? ""
            isBold = nameTraits?.contains(.traitBold) == true || styleName.contains("bold")
            isItalic =
                nameTraits?.contains(.traitItalic) == true
                || styleName.contains("italic") || styleName.contains("oblique")
        }
        guard size != nil || family != nil || isBold || isItalic || color != nil else { return nil }
        return TypeStyle(size: size, family: family, isBold: isBold, isItalic: isItalic, color: color)
    }

    /// The text colour at the start of an attributed string, from the Accessibility key or the Core Text one.
    static func textColor(inAttributed attributed: CFAttributedString) -> TextColor? {
        let keys = [Self.axForegroundColorKey as CFString, kCTForegroundColorAttributeName]
        for key in keys {
            if let color = textColor(CFAttributedStringGetAttribute(attributed, 0, key, nil)) { return color }
        }
        return nil
    }

    /// A Core Graphics colour as sRGB, or nothing for a value that is not one or cannot be converted.
    static func textColor(_ value: CFTypeRef?) -> TextColor? {
        guard let value, CFGetTypeID(value) == CGColor.typeID,
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        let color = unsafeDowncast(value, to: CGColor.self)
        guard let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
            let channels = converted.components, channels.count >= 3
        else { return nil }
        return TextColor(red: Double(channels[0]), green: Double(channels[1]), blue: Double(channels[2]))
    }

    /// The attribute Accessibility describes a run's font under, which is a dictionary rather than a font object.
    private static let axFontKey = "AXFont"
    private static let axFontSizeKey = "AXFontSize"
    private static let axFontFamilyKey = "AXFontFamily"
    private static let axFontNameKey = "AXFontName"
    private static let axFontStyleKey = "AXFontStyle"
    private static let axForegroundColorKey = "AXForegroundColor"

    /// The selection as a character range, measured in text markers from the field's start, for a field that refuses `AXSelectedTextRange`.
    static func markerSelection(_ field: AXUIElement) -> MarkerSelection? {
        var selected: AnyObject?
        guard
            AXUIElementCopyAttributeValue(field, "AXSelectedTextMarkerRange" as CFString, &selected)
                == .success,
            let selected, CFGetTypeID(selected) == AXTextMarkerRangeGetTypeID(),
            let whole = SurfaceProbe.parameterized(field, "AXTextMarkerRangeForUIElement", field),
            CFGetTypeID(whole) == AXTextMarkerRangeGetTypeID()
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        let selection = unsafeDowncast(selected, to: AXTextMarkerRange.self)
        let all = unsafeDowncast(whole, to: AXTextMarkerRange.self)
        let start = AXTextMarkerRangeCopyStartMarker(all)
        let before = AXTextMarkerRangeCreate(nil, start, AXTextMarkerRangeCopyStartMarker(selection))
        guard let location = markerLength(field, before), let length = markerLength(field, selection),
            let count = markerLength(field, all)
        else { return nil }
        return MarkerSelection(range: NSRange(location: location, length: length), count: count)
    }

    /// How many characters a text-marker range spans, or nothing where the field will not count them.
    private static func markerLength(_ field: AXUIElement, _ range: AXTextMarkerRange) -> Int? {
        (SurfaceProbe.parameterized(field, "AXLengthForTextMarkerRange", range) as? NSNumber)?.intValue
    }

    /// The screen rectangle of the selection's text-marker range, which web content answers where it answers nothing for a character range.
    private static func markerBounds(_ field: AXUIElement) -> CGRect? {
        var marker: AnyObject?
        guard
            AXUIElementCopyAttributeValue(field, "AXSelectedTextMarkerRange" as CFString, &marker)
                == .success,
            let marker
        else { return nil }
        var answer: AnyObject?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                field, "AXBoundsForTextMarkerRange" as CFString, marker, &answer) == .success,
            let answer, CFGetTypeID(answer) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        guard AXValueGetValue(unsafeDowncast(answer, to: AXValue.self), .cgRect, &rect), !rect.isNull
        else { return nil }
        return rect
    }

}
