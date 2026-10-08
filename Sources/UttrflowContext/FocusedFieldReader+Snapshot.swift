import CoreGraphics
import Foundation
import UttrflowCore
import UttrflowPredict

/// The focused-field read decided over any `ElementTree`, so every refusal and fallback in it is testable.
extension FocusedFieldReader {
    /// The answers that hold for one field in one window, kept so the next read of it skips them.
    struct StableAnswers: Sendable {
        let identity: FieldNames
        let document: String?
        let fieldFrame: CGRect?
        let windowFrame: CGRect?
        let windowTitle: String?
    }

    /// What one read takes from outside the tree: the app, the decoder, the cache and the system's own answers.
    struct SnapshotSources<Element> {
        let app: FrontmostApp
        let decode: FieldAnswerDecoder<Element>
        /// The answers kept for the field in this window, and where a first read keeps its own.
        let cached: (_ window: Element?) -> StableAnswers?
        let keep: (StableAnswers, _ window: Element?) -> Void
        /// The field's identity within its process, and the system window that holds it.
        let elementHash: (Element) -> UInt
        let windowNumber: (Element) -> UInt32?
        /// Where the primary screen ends, which input source is selected, and how long the read has run.
        let primaryScreenMaxY: () -> CGFloat
        let inputSourceKind: () -> InputSourceKind
        let elapsedMicroseconds: () -> Int
    }

    /// Everything the snapshot holds, each question asked once and none after `goOn` says stop.
    static func snapshot<Tree: ElementTree>(
        of field: Tree.Element, in tree: Tree, from sources: SnapshotSources<Tree.Element>,
        while goOn: () -> Bool
    ) -> FocusedFieldSnapshot? {
        Ladder(tree: tree, field: field, sources: sources).read(while: goOn)
    }

    /// Reads a window number only while this field snapshot is still wanted.
    static func windowNumber(while isWanted: () -> Bool, read: () -> UInt32?) -> UInt32? {
        guard isWanted() else { return nil }
        let number = read()
        guard isWanted() else { return nil }
        return number
    }

    /// The field's own answers, read before its caret is placed.
    private struct FieldState {
        let role: String
        let stable: StableAnswers
        let range: CFRange?
        let text: FieldText
        let style: TypeStyle?
        let marked: MarkedText
        let showsOwnList: Bool
        let isEnabled: Bool?
        let isEditable: Bool?
    }

    /// Where the caret sits, and what the window around the field adds to it.
    private struct Placement {
        let caret: CaretLocator.Result?
        let showsOwnList: Bool
        let hidden: HiddenInputLine.Reading?
        let windowNumber: UInt32?
    }

    /// One read of one field, in the order its questions are asked.
    private struct Ladder<Tree: ElementTree> {
        let tree: Tree
        let field: Tree.Element
        let sources: SnapshotSources<Tree.Element>

        func read(while goOn: () -> Bool) -> FocusedFieldSnapshot? {
            let window = tree.attribute("AXWindow", of: field)
            guard goOn(), let state = state(in: window, while: goOn) else { return nil }
            let caret = caret(for: state, while: goOn)
            guard goOn() else { return nil }
            // A fresh window element, so the picker asks the window as it is now rather than the answers kept above.
            let picker =
                state.showsOwnList
                || window.object.flatMap(sources.decode.element).map {
                    FocusedWindowPicker.isOpen(in: $0, near: state.stable.fieldFrame, using: tree, while: goOn)
                } ?? false
            guard goOn() else { return nil }
            // An editor that draws its own text keeps an empty input at the caret, so its line is read off the rendered text.
            let hidden = state.text.isSecure ? nil : hiddenInputLine(for: state, while: goOn)
            let number = FocusedFieldReader.windowNumber(while: goOn) { sources.windowNumber(field) }
            guard goOn() else { return nil }
            return snapshot(
                state,
                Placement(caret: caret, showsOwnList: picker, hidden: hidden, windowNumber: number))
        }

        /// The field's answers up to its caret, or nothing for a field with no role or several selections.
        private func state(in windowAnswer: FieldAnswer, while goOn: () -> Bool) -> FieldState? {
            let window = windowAnswer.object.flatMap(sources.decode.element)
            let cached = sources.cached(window)
            let identity = cached?.identity ?? FocusedFieldRead.names(of: field, in: tree)
            guard let role = identity.role, goOn(),
                let stable = cached ?? stableAnswers(identity: identity, window: window, while: goOn),
                goOn(), let range = range(names: stable.identity, while: goOn), goOn()
            else { return nil }
            let text = FocusedFieldRead.text(
                of: field, in: tree, names: stable.identity,
                at: range.map { NSRange(location: $0.location, length: $0.length) })
            guard goOn() else { return nil }
            // The attributed string carries the characters, so a secure field is never asked for its style.
            let style = text.isSecure ? nil : range.flatMap { typeStyle(at: boundedStyleRange($0)) }
            guard goOn() else { return nil }
            let marked = FocusedFieldRead.markedText(of: field, in: tree, decode: sources.decode)
            guard goOn() else { return nil }
            // A combobox field says when its own list is open, one flag on the field itself.
            let ownList = tree.attribute("AXExpanded", of: field).integer == 1
            guard goOn() else { return nil }
            let isEnabled = tree.attribute("AXEnabled", of: field).boolean
            guard goOn() else { return nil }
            let isEditable = tree.attribute("AXIsEditable", of: field).boolean
            guard goOn() else { return nil }
            return FieldState(
                role: role, stable: stable, range: range, text: text, style: style, marked: marked,
                showsOwnList: ownList, isEnabled: isEnabled, isEditable: isEditable)
        }

        /// The answers a first read of this field in this window asks, kept for the reads after it.
        private func stableAnswers(
            identity: FieldNames, window: Tree.Element?, while goOn: () -> Bool
        ) -> StableAnswers? {
            let fieldDocument = tree.attribute("AXDocument", of: field).string
            guard goOn() else { return nil }
            let document = fieldDocument ?? window.flatMap { tree.document(of: $0) }
            guard goOn() else { return nil }
            let fieldFrame = frame()
            guard goOn() else { return nil }
            let windowFrame = window.flatMap { tree.frame(of: $0) }
            guard goOn() else { return nil }
            let windowTitle = window.flatMap { tree.title(of: $0) }
            guard goOn() else { return nil }
            let answers = StableAnswers(
                identity: identity, document: document, fieldFrame: fieldFrame, windowFrame: windowFrame,
                windowTitle: windowTitle)
            sources.keep(answers, window)
            return answers
        }

        /// The selection as a range, from the marker rung where the field refuses one, and nothing at all for several.
        private func range(names: FieldNames, while goOn: () -> Bool) -> CFRange?? {
            switch FocusedFieldRead.selection(of: field, in: tree, decode: sources.decode) {
            case .discontinuous: return nil
            case .range(let range): return .some(range)
            case .unavailable:
                // Decided before any marker read, so a secure or unknown field is not read further.
                guard !names.isSecureOrUnknown, goOn(), let marker = tree.markerSelection(of: field) else {
                    return .some(nil)
                }
                return CFRange(location: marker.range.location, length: marker.range.length)
            }
        }

        /// The caret's screen rectangle, from the selection where the field answers it and from the text marker where it does not.
        private func caret(for state: FieldState, while goOn: () -> Bool) -> CaretLocator.Result? {
            let direction = paragraphDirection(for: state, while: goOn)
            return CaretLocator.result(
                at: state.range.map { (location: $0.location, length: $0.length) },
                frame: state.stable.fieldFrame, pointSize: state.style?.size, value: state.text.value,
                textSelectionLocation: state.text.selection?.location, paragraphDirection: direction,
                bounds: { goOn() ? bounds(at: CFRange(location: $0, length: $1)) : nil },
                markerBounds: { goOn() ? tree.markerBounds(of: field) : nil })
        }

        /// The direction of the paragraph a caret at the end of the field sits in, read off the character before it.
        private func paragraphDirection(for state: FieldState, while goOn: () -> Bool) -> WritingDirection {
            guard let range = state.range, range.length == 0, range.location > 0,
                state.text.selection?.length == 0,
                state.text.selection?.location == state.text.value?.utf16.count,
                !state.text.isSecure, goOn(),
                let attributed = attributedString(at: CFRange(location: range.location - 1, length: 1))
            else { return .unknown }
            return FocusedFieldReader.writingDirection(inAttributed: attributed)
        }

        /// The caret's line read off an editor's rendered text, for the empty caret-sized input such an editor keeps focused.
        private func hiddenInputLine(for state: FieldState, while goOn: () -> Bool) -> HiddenInputLine.Reading? {
            let probe = HiddenInputLine.probe(
                field, role: state.role, value: state.text.value, frame: { state.stable.fieldFrame }, in: tree,
                while: goOn)
            guard case .line(let reading) = probe else { return nil }
            return reading
        }

        /// The font at the caret, so the ghost is set in the field's own face and size.
        private func typeStyle(at range: CFRange) -> TypeStyle? {
            attributedString(at: AccessibilityRange.widenedForStyle(range))
                .flatMap(FocusedFieldReader.typeStyle(inAttributed:))
        }

        /// The field's attributed text over one range, or nothing where it answers something else.
        private func attributedString(at range: CFRange) -> CFAttributedString? {
            let answer = tree.attribute(
                "AXAttributedStringForRange", of: field,
                range: NSRange(location: range.location, length: range.length))
            guard let object = answer.object.map({ $0 as AnyObject }),
                CFGetTypeID(object) == CFAttributedStringGetTypeID()
            else { return nil }
            // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
            return unsafeDowncast(object, to: CFAttributedString.self)
        }

        /// The screen rectangle the field reports for one text range, which decides whether a ghost can be drawn.
        private func bounds(at range: CFRange) -> CGRect? {
            let answer = tree.attribute(
                "AXBoundsForRange", of: field, range: NSRange(location: range.location, length: range.length))
            return answer.object.flatMap(sources.decode.rect).flatMap { $0.isNull ? nil : $0 }
        }

        /// The field's rectangle, or nothing when it gives no position or no size.
        private func frame() -> CGRect? {
            guard let origin = tree.attribute("AXPosition", of: field).object.flatMap(sources.decode.point),
                let size = tree.attribute("AXSize", of: field).object.flatMap(sources.decode.size)
            else { return nil }
            return CGRect(origin: origin, size: size)
        }

        /// Bounds an attributed style read at the start of a selection.
        private func boundedStyleRange(_ range: CFRange) -> CFRange {
            CFRange(location: range.location, length: min(range.length, ValueWindow.selectionLimit))
        }

        /// The snapshot the answers make, every rectangle turned from Accessibility's measure to AppKit's.
        private func snapshot(_ state: FieldState, _ placement: Placement) -> FocusedFieldSnapshot {
            let below = sources.primaryScreenMaxY()
            let flip = { SuggestionGeometry.fromAccessibility($0, primaryScreenMaxY: below) }
            let (identity, stable, text, style, hidden) =
                (state.stable.identity, state.stable, state.text, state.style, placement.hidden)
            return FocusedFieldSnapshot(
                bundleIdentifier: sources.app.bundleIdentifier, applicationName: sources.app.name,
                role: state.role, subrole: identity.subrole, identifier: identity.identifier,
                placeholder: identity.placeholder, accessibilityDescription: identity.description,
                document: stable.document,
                value: text.isSecure ? nil : hidden.map { $0.before + $0.after } ?? text.value,
                selection: hidden.map { NSRange(location: $0.before.utf16.count, length: 0) } ?? text.selection,
                focusedFieldIdentity: FocusedFieldIdentity(
                    processIdentifier: sources.app.processIdentifier, elementHash: sources.elementHash(field)),
                caret: (hidden?.caret ?? placement.caret?.caret).map(flip),
                writingDirection: hidden == nil ? placement.caret?.direction ?? .unknown : .unknown,
                window: stable.windowFrame.map(flip),
                field: (hidden?.line ?? stable.fieldFrame).flatMap {
                    FocusedFieldSnapshot.isCaretShaped($0) ? nil : flip($0)
                },
                pointSize: style?.size, fontFamily: style?.family, isBold: style?.isBold ?? false,
                isItalic: style?.isItalic ?? false, textColor: style?.color, isSecure: text.isSecure,
                isEnabled: state.isEnabled, isEditable: state.isEditable,
                isComposing: Composition.isComposing(
                    markedText: state.marked, inputSource: sources.inputSourceKind()),
                markedText: state.marked, showsOwnList: placement.showsOwnList,
                readMicroseconds: sources.elapsedMicroseconds(), windowTitle: stable.windowTitle,
                windowNumber: placement.windowNumber)
        }
    }
}
