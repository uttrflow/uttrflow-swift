import AppKit
import ApplicationServices
import CoreText
import Foundation
import UttrflowPredict

private import Synchronization

/// The frontmost application's identity, taken on the main thread where `NSWorkspace` is safe to read.
public struct FrontmostApp: Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String
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
    private static let queue = DispatchQueue(label: "com.uttrflow.focused-field", qos: .userInitiated)

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

    /// The frontmost application's identity, read on the main thread the one place `NSWorkspace` allows.
    @MainActor
    public static func frontmostApp() -> FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = app.bundleIdentifier
        else { return nil }
        // Some applications pad their name with control and direction marks, which would reach the model verbatim.
        let name = Surroundings.cleaned(app.localizedName ?? bundleIdentifier)
            .trimmingCharacters(in: .whitespaces)
        return FrontmostApp(
            processIdentifier: app.processIdentifier, bundleIdentifier: bundleIdentifier,
            name: name.isEmpty ? bundleIdentifier : name)
    }

    /// One reading, off the main thread, or `nil` when nothing usable is focused.
    public static func read() async -> FocusedFieldSnapshot? {
        // Identity is taken on the main actor first, because the blocking read below may not touch `NSWorkspace`.
        guard let app = await frontmostApp() else { return nil }
        // A field that stops answering costs the turn half a second at most; the read finishes on its queue regardless.
        return await Deadline.first(withinMilliseconds: 500) {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: snapshot(app: app)) }
            }
        }
    }

    /// Its own thread for the wider walk, so an application slow to describe its window never holds up a field read.
    private static let surroundingsQueue = DispatchQueue(
        label: "com.uttrflow.surroundings", qos: .utility)

    /// How long one Accessibility call into another application may wait, since a stalled one would otherwise wait seconds.
    static let elementTimeoutInSeconds: Float = 0.05

    /// What is on screen around the focused field, or `nil` when nothing usable is focused or the wait ran out.
    public static func surroundings(withinMilliseconds allowance: Int = 200) async -> Surroundings? {
        guard let app = await frontmostApp() else { return nil }
        // A read that does not answer in time is left to finish on its queue; the turn goes on without it.
        return await Deadline.first(withinMilliseconds: allowance) {
            await withCheckedContinuation { continuation in
                surroundingsQueue.async { continuation.resume(returning: surroundings(app: app)) }
            }
        }
    }

    /// The same read for a named application, front or not, which is how a probe shows what the model would be shown.
    public static func surroundings(of app: FrontmostApp) -> Surroundings? {
        surroundings(app: app)
    }

    /// The same read, synchronously, which only the queue above calls with an identity read on main.
    static func surroundings(app: FrontmostApp) -> Surroundings? {
        // A field with no window, or a window focused as a whole, has nothing around it worth a walk.
        guard AXIsProcessTrusted(), let field = SurfaceProbe.focusedField(of: app.processIdentifier),
            let window = element(field, kAXWindowAttribute), !CFEqual(field, window)
        else { return nil }
        let answers = AXNode(window).answers
        return Surroundings.collect(
            around: AXNode(field), in: AXElementTree(), windowTitle: answers.title, windowFrame: answers.frame
        )
    }

    /// The same reading, synchronously, which only the queue above calls with an identity read on main.
    static func snapshot(app: FrontmostApp) -> FocusedFieldSnapshot? {
        let started = DispatchTime.now().uptimeNanoseconds
        guard AXIsProcessTrusted(), let field = SurfaceProbe.focusedField(of: app.processIdentifier)
        else { return nil }
        // Every question to the field gives up quickly, so a field that stops answering costs a moment, not the loop.
        _ = AXUIElementSetMessagingTimeout(field, elementTimeoutInSeconds)
        guard let role = string(field, kAXRoleAttribute) else { return nil }

        let subrole = string(field, kAXSubroleAttribute)
        let identifier = string(field, kAXIdentifierAttribute)
        let placeholder = string(field, kAXPlaceholderValueAttribute)
        let description = string(field, kAXDescriptionAttribute)
        // Decided before the value is fetched, so a declared secure field's contents are never read at all.
        let declaredSecure = SecureField.isDeclaredSecure(
            role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
            description: description)
        let value = declaredSecure ? nil : string(field, kAXValueAttribute)
        let secure = declaredSecure || (value.map(SecureField.looksMasked) ?? false)
        let range: CFRange? = axValue(field, kAXSelectedTextRangeAttribute, .cfRange)
        let style = range.flatMap { typeStyle(field, at: $0) }
        let flipped = cachedPrimaryScreenMaxY.withLock { $0 }

        return FocusedFieldSnapshot(
            bundleIdentifier: app.bundleIdentifier,
            applicationName: app.name,
            role: role,
            subrole: subrole,
            identifier: identifier,
            placeholder: placeholder,
            accessibilityDescription: description,
            document: document(of: field),
            value: secure ? nil : value,
            selection: range.map { NSRange(location: $0.location, length: $0.length) },
            caret: range.flatMap { caret(field, at: $0) }.map { flip($0, below: flipped) },
            window: windowFrame(of: field).map { flip($0, below: flipped) },
            pointSize: style?.size,
            fontFamily: style?.family,
            isSecure: secure,
            isComposing: Composition.isComposing(
                markedText: markedText(field), inputSource: CompositionProbe.inputSourceKind()),
            readMicroseconds: Int((DispatchTime.now().uptimeNanoseconds - started) / 1000)
        )
    }

    /// What this field says about an input method's marked text. See `Docs/predict-ime.md`.
    private static func markedText(_ field: AXUIElement) -> MarkedText {
        guard let range: CFRange = axValue(field, "AXTextInputMarkedRange", .cfRange) else {
            return .unanswered
        }
        return range.length > 0 ? .present : .absent
    }

    /// Accessibility measures from the top of the primary screen; AppKit measures from the bottom.
    private static func flip(_ rect: CGRect, below primaryScreenMaxY: CGFloat) -> CGRect {
        SuggestionGeometry.fromAccessibility(rect, primaryScreenMaxY: primaryScreenMaxY)
    }

    /// The page or the directory the field belongs to, which the window publishes when the field does not.
    private static func document(of field: AXUIElement) -> String? {
        if let own = string(field, kAXDocumentAttribute) { return own }
        guard let window = element(field, kAXWindowAttribute) else { return nil }
        return string(window, kAXDocumentAttribute)
    }

    /// The window's rectangle, which is what the strip stands on when no caret can be read.
    private static func windowFrame(of field: AXUIElement) -> CGRect? {
        guard let window = element(field, kAXWindowAttribute),
            let origin: CGPoint = axValue(window, kAXPositionAttribute, .cgPoint),
            let size: CGSize = axValue(window, kAXSizeAttribute, .cgSize)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The caret's screen rectangle, read off the glyph beside it because its own zero-length bounds lies.
    private static func caret(_ field: AXUIElement, at range: CFRange) -> CGRect? {
        // A real selection, unlike a caret, reports its own bounds honestly.
        if range.length > 0, let rect = bounds(field, range), rect.height > 0 { return rect }
        let location = range.location
        // The caret sits at the trailing edge of the glyph before it, which is what typing just moved past.
        if location > 0, let before = bounds(field, CFRange(location: location - 1, length: 1)),
            before.height > 0
        {
            return CGRect(x: before.maxX, y: before.minY, width: 0, height: before.height)
        }
        // At the very start there is no glyph before, so the caret takes the leading edge of the one after.
        if let at = bounds(field, CFRange(location: location, length: 1)), at.height > 0 {
            return CGRect(x: at.minX, y: at.minY, width: 0, height: at.height)
        }
        // An empty line has no glyph beside the caret, so its own bounds is all there is.
        if let rect = bounds(field, range), rect.height > 0 { return rect }
        // A web field answers glyph bounds with a zero-size rectangle, but its selection's text-marker range still has a place on screen.
        if let rect = markerBounds(field), rect.height > 0 {
            return CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height)
        }
        // An editor that draws its own text keeps a one-pixel field at the caret for input methods, so that field's frame is the caret.
        if let frame = AXNode(field).answers.frame, FocusedFieldSnapshot.isCaretShaped(frame) {
            return CGRect(x: frame.minX, y: frame.minY, width: 0, height: frame.height)
        }
        return nil
    }

    /// The screen rectangle Accessibility reports for one text range, or nothing when it will not say.
    private static func bounds(_ field: AXUIElement, _ range: CFRange) -> CGRect? {
        guard let answer = parameterized(field, kAXBoundsForRangeParameterizedAttribute, range),
            CFGetTypeID(answer) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        guard AXValueGetValue(unsafeDowncast(answer, to: AXValue.self), .cgRect, &rect), !rect.isNull
        else { return nil }
        return rect
    }

    /// What a field says about its own type, either half of which it may leave out.
    struct TypeStyle: Sendable, Equatable {
        let size: CGFloat?
        let family: String?
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

        static func == (lhs: AXNode, rhs: AXNode) -> Bool { CFEqual(lhs.element, rhs.element) }
    }

    /// Everything the collector asks one element, fetched in a single message the first time any of it is needed.
    final class Answers {
        /// The attributes asked for, in the order the answers come back.
        private static let attributes = [
            kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXValueAttribute, kAXTitleAttribute,
            kAXDescriptionAttribute, kAXChildrenAttribute, kAXParentAttribute,
        ]

        private let element: AXUIElement
        private var fetched: [AnyObject]?

        init(_ element: AXUIElement) {
            self.element = element
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
        var title: String? { self[kAXTitleAttribute] as? String }

        /// What the element says: its value, else its title, else its description, which is where a chat keeps its messages.
        var text: String? {
            for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let text = self[attribute] as? String, text.contains(where: { !$0.isWhitespace }) {
                    return text
                }
            }
            return nil
        }

        /// Where the element is, or nothing when it reports no position or no size.
        var frame: CGRect? {
            guard let origin: CGPoint = unwrap(self[kAXPositionAttribute], .cgPoint),
                let size: CGSize = unwrap(self[kAXSizeAttribute], .cgSize)
            else { return nil }
            return CGRect(origin: origin, size: size)
        }

        var children: [AXUIElement] { self[kAXChildrenAttribute] as? [AXUIElement] ?? [] }

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
        func text(of node: AXNode) -> String? { node.answers.text }
        func frame(of node: AXNode) -> CGRect? { node.answers.frame }
        func children(of node: AXNode) -> [AXNode] { node.answers.children.map(AXNode.init) }

        /// The element's parent, stopping at the window so the walk never crosses into the application's other windows.
        func parent(of node: AXNode) -> AXNode? {
            guard node.answers.role != kAXWindowRole, let parent = node.answers.parent.map(AXNode.init),
                parent.answers.role != kAXApplicationRole
            else { return nil }
            return parent
        }
    }

    /// The font at the caret, so the ghost is set in the field's own face and size.
    private static func typeStyle(_ field: AXUIElement, at range: CFRange) -> TypeStyle? {
        let widened =
            range.length > 0 ? range : CFRange(location: max(range.location - 1, 0), length: 1)
        guard
            let answer = parameterized(
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

    /// The font in an attributed string: a Core Text font where AppKit put one, else the `AXFont` dictionary most applications answer with.
    static func typeStyle(inAttributed attributed: CFAttributedString) -> TypeStyle? {
        guard CFAttributedStringGetLength(attributed) > 0 else { return nil }
        if let font = CFAttributedStringGetAttribute(attributed, 0, kCTFontAttributeName, nil),
            CFGetTypeID(font) == CTFontGetTypeID()
        {
            // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
            let font = unsafeDowncast(font, to: CTFont.self)
            return TypeStyle(size: CTFontGetSize(font), family: CTFontCopyFamilyName(font) as String)
        }
        guard
            let described = CFAttributedStringGetAttribute(attributed, 0, Self.axFontKey as CFString, nil),
            CFGetTypeID(described) == CFDictionaryGetTypeID()
        else { return nil }
        // Checked by type ID above; a Core Foundation dictionary bridges to Foundation without AppKit.
        let font = unsafeDowncast(described, to: CFDictionary.self) as NSDictionary
        let size = (font[Self.axFontSizeKey] as? NSNumber).map { CGFloat($0.doubleValue) }
        let family = font[Self.axFontFamilyKey] as? String
        guard size != nil || family != nil else { return nil }
        return TypeStyle(size: size, family: family)
    }

    /// The attribute Accessibility describes a run's font under, which is a dictionary rather than a font object.
    private static let axFontKey = "AXFont"
    private static let axFontSizeKey = "AXFontSize"
    private static let axFontFamilyKey = "AXFontFamily"

    /// One `AXValue` attribute, unwrapped into the Core Graphics type it stands for.
    private static func axValue<T>(
        _ owner: AXUIElement, _ attribute: String, _ kind: AXValueType
    ) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success else {
            return nil
        }
        return unwrap(value, kind)
    }

    /// One `AXValue`, already fetched, unwrapped into the Core Graphics type it stands for.
    private static func unwrap<T>(_ value: AnyObject?, _ kind: AXValueType) -> T? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        let unwrapped = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { unwrapped.deallocate() }
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), kind, unwrapped) else {
            return nil
        }
        return unwrapped.pointee
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

    private static func parameterized(
        _ field: AXUIElement, _ attribute: String, _ range: CFRange
    ) -> AnyObject? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var answer: AnyObject?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                field, attribute as CFString, parameter, &answer) == .success
        else { return nil }
        return answer
    }

    private static func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        let element = unsafeDowncast(value, to: AXUIElement.self)
        // A window or parent reached from the field answers under the same short timeout as the field itself.
        _ = AXUIElementSetMessagingTimeout(element, elementTimeoutInSeconds)
        return element
    }

    private static func string(_ owner: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
