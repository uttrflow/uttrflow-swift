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
        return FrontmostApp(
            processIdentifier: app.processIdentifier, bundleIdentifier: bundleIdentifier,
            name: app.localizedName ?? bundleIdentifier)
    }

    /// One reading, off the main thread, or `nil` when nothing usable is focused.
    public static func read() async -> FocusedFieldSnapshot? {
        // Identity is taken on the main actor first, because the blocking read below may not touch `NSWorkspace`.
        guard let app = await frontmostApp() else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: snapshot(app: app)) }
        }
    }

    /// The same reading, synchronously, which only the queue above calls with an identity read on main.
    static func snapshot(app: FrontmostApp) -> FocusedFieldSnapshot? {
        let started = DispatchTime.now().uptimeNanoseconds
        guard AXIsProcessTrusted(),
            let field = SurfaceProbe.focusedField(of: app.processIdentifier),
            let role = string(field, kAXRoleAttribute)
        else { return nil }

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
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        let unwrapped = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { unwrapped.deallocate() }
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), kind, unwrapped) else {
            return nil
        }
        return unwrapped.pointee
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
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ owner: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
