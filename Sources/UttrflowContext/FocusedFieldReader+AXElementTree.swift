import ApplicationServices
import Foundation
import UttrflowCore

/// The Accessibility side of `ElementTree`, which the focused-field read and the surroundings walk message another app through.
extension FocusedFieldReader {
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
            _ = AXUIElementCopyMultipleAttributeValues(
                element, Self.attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &answers)
            let values = answers as? [AnyObject] ?? []
            fetched = Self.padded(values, to: Self.attributes.count)
            return fetched ?? []
        }

        /// Preserves each position returned by a batch even when another attribute failed.
        static func padded(_ values: [AnyObject], to count: Int) -> [AnyObject] {
            Array(values.prefix(count)) + Array(repeating: kCFNull, count: max(0, count - values.count))
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
            guard Self.securityAttributes.allSatisfy({ hasUsableSecurityAnswer(for: $0) }) else {
                return true
            }
            return SecureField.isDeclaredSecureOnScreen(
                role: role, subrole: self[kAXSubroleAttribute] as? String,
                identifier: self[kAXIdentifierAttribute] as? String,
                placeholder: self[kAXPlaceholderValueAttribute] as? String,
                description: self[kAXDescriptionAttribute] as? String,
                title: self[kAXTitleAttribute] as? String)
        }

        /// The role is required; errors in optional security names fail closed except when explicitly unsupported/empty.
        private static let securityAttributes = [
            kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute,
            kAXPlaceholderValueAttribute, kAXDescriptionAttribute,
            kAXTitleAttribute,
        ]

        private func hasUsableSecurityAnswer(for attribute: String) -> Bool {
            guard let value = self[attribute] else { return false }
            if attribute == kAXRoleAttribute { return value as? String != nil }
            if CFGetTypeID(value) == CFNullGetTypeID() { return true }
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return value as? String != nil }
            let axValue = unsafeDowncast(value, to: AXValue.self)
            guard AXValueGetType(axValue) == .axError else { return true }
            var error = AXError.failure
            guard AXValueGetValue(axValue, .axError, &error) else { return false }
            return error == .attributeUnsupported || error == .noValue
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
        func title(of node: AXNode) -> String? { node.answers.title }
        func document(of node: AXNode) -> String? { node.answers.document }
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

        /// The screen rectangle of the selection's text-marker range, which web content answers where it answers nothing for a character range.
        func markerBounds(of node: AXNode) -> CGRect? {
            var marker: AnyObject?
            guard
                AXUIElementCopyAttributeValue(node.element, "AXSelectedTextMarkerRange" as CFString, &marker)
                    == .success,
                let marker
            else { return nil }
            var answer: AnyObject?
            guard
                AXUIElementCopyParameterizedAttributeValue(
                    node.element, "AXBoundsForTextMarkerRange" as CFString, marker, &answer) == .success,
                let answer, CFGetTypeID(answer) == AXValueGetTypeID()
            else { return nil }
            var rect = CGRect.zero
            // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
            guard AXValueGetValue(unsafeDowncast(answer, to: AXValue.self), .cgRect, &rect), !rect.isNull
            else { return nil }
            return rect
        }

        /// Reads every attribute in one message and keeps any partial answers returned by Accessibility.
        func attributes(_ names: [String], of node: AXNode) -> [FieldAnswer] {
            var answers: CFArray?
            let started = DispatchTime.now().uptimeNanoseconds
            let result = AXUIElementCopyMultipleAttributeValues(
                node.element, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &answers)
            let elapsed = DispatchTime.now().uptimeNanoseconds - started
            return Self.decodeBatch(
                answers as? [AnyObject], count: names.count, error: result,
                elapsedSeconds: Double(elapsed) / 1_000_000_000)
        }

        /// Decodes returned slots positionally; missing slots fail closed without a second AX request.
        static func decodeBatch(
            _ values: [AnyObject]?, count: Int, error: AXError, elapsedSeconds: Double
        ) -> [FieldAnswer] {
            (0..<count).map { index in
                guard let values, values.indices.contains(index) else {
                    return FieldAnswer.classify(
                        code: error == .success ? AXError.noValue.rawValue : error.rawValue,
                        value: nil, elapsedSeconds: elapsedSeconds,
                        timeoutSeconds: Double(elementTimeoutInSeconds))
                }
                let value = values[index]
                if CFGetTypeID(value) == CFNullGetTypeID() { return .noValue }
                guard CFGetTypeID(value) == AXValueGetTypeID() else { return .value(value) }
                let axValue = unsafeDowncast(value, to: AXValue.self)
                guard AXValueGetType(axValue) == .axError else { return .value(value) }
                var slotError = AXError.failure
                guard AXValueGetValue(axValue, .axError, &slotError) else { return .unsupported }
                return FieldAnswer.classify(
                    code: slotError.rawValue, value: nil, elapsedSeconds: elapsedSeconds,
                    timeoutSeconds: Double(elementTimeoutInSeconds))
            }
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
}
