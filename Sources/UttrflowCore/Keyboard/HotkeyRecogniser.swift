// Decides whether a stream of keystrokes is the shortcut being pressed and released.

/// Turns keystrokes into one binding's press and release, whatever shape the binding is.
public struct HotkeyRecogniser: Sendable, Equatable {
    /// The shortcut being watched for.
    public let binding: HotkeyBinding
    /// Whether the shortcut is currently down, as far as the strokes seen say.
    public var isDown: Bool { edge.isDown }

    /// The press-and-release rule, shared with every other thing that watches a key go down.
    private var edge = HeldModifierEdge()
    /// Whether the held modifiers were used by another shortcut, which lasts until every modifier is up.
    private var isSpoiled = false
    /// Whether Fn began another shortcut, which lasts until Fn is up.
    private var functionHoldIsSpoiled = false
    /// Whether a combination key is down, independent of changes to its modifiers.
    private var combinationKeyIsDown = false

    public init(binding: HotkeyBinding) {
        self.binding = binding
    }

    /// The press or release this stroke completes, or nothing when the state did not change.
    public mutating func receive(_ stroke: KeyEvent) -> HotkeyEvent? {
        if binding.isFunctionHold { return receiveFunctionHold(stroke) }
        if binding.heldModifier != nil { return receiveModifierHold(stroke) }
        return receiveCombination(stroke)
    }

    /// A combination stays held while its key is down and its own modifiers are, whatever other modifiers change.
    private mutating func receiveCombination(_ stroke: KeyEvent) -> HotkeyEvent? {
        switch stroke.phase {
        case .down:
            guard stroke.keyCode == binding.keyCode, stroke.modifiers == binding.modifiers else { return nil }
            combinationKeyIsDown = true
            return settle(true)
        case .up:
            guard stroke.keyCode == binding.keyCode, combinationKeyIsDown else { return nil }
            combinationKeyIsDown = false
            return settle(false)
        case .modifiersChanged:
            // A flags change names the modifier key that moved, never the combination's own key.
            guard combinationKeyIsDown, !stroke.modifiers.isSuperset(of: binding.modifiers) else {
                return nil
            }
            combinationKeyIsDown = false
            return settle(false)
        }
    }

    /// Fn held, read only from a flags change: an arrow key carries the same flag without being Fn.
    private mutating func receiveFunctionHold(_ stroke: KeyEvent) -> HotkeyEvent? {
        defer {
            if !stroke.isFunctionDown { functionHoldIsSpoiled = false }
        }
        guard stroke.phase == .modifiersChanged else {
            if stroke.phase == .down, stroke.isFunctionDown { functionHoldIsSpoiled = true }
            return functionHoldIsSpoiled && edge.stopped() != nil ? .cancelled : nil
        }
        let event: HotkeyEvent?
        if functionHoldIsSpoiled {
            event = edge.stopped() == nil ? nil : .cancelled
        } else {
            event = settle(stroke.isFunctionDown)
        }
        return event
    }

    /// Modifiers held alone, withdrawn when a key or another modifier shows they begin a different shortcut.
    private mutating func receiveModifierHold(_ stroke: KeyEvent) -> HotkeyEvent? {
        if stroke.modifiers.isEmpty { isSpoiled = false }
        if beginsAnotherShortcut(stroke) { isSpoiled = true }
        guard isSpoiled else { return settle(matches(stroke)) }
        return edge.stopped() == nil ? nil : .cancelled
    }

    /// Whether this stroke uses the held modifiers for something else: a key typed, or a modifier the binding lacks.
    private func beginsAnotherShortcut(_ stroke: KeyEvent) -> Bool {
        if stroke.phase == .down, !stroke.modifiers.isEmpty { return true }
        return !stroke.modifiers.isSubset(of: heldModifiers)
    }

    /// A release owed because watching stopped mid-hold, or nothing when nothing was held.
    public mutating func finish() -> HotkeyEvent? {
        combinationKeyIsDown = false
        return settle(false)
    }

    /// Whether this stroke is the binding held right now.
    private func matches(_ stroke: KeyEvent) -> Bool {
        guard !binding.modifiers.isEmpty || binding.heldModifier != nil else { return false }
        // A held modifier is down when exactly its own modifiers are, and nothing else.
        if binding.heldModifier != nil, binding.modifiers.isEmpty {
            return stroke.modifiers == modifiersOfHeldKey && !stroke.isFunctionDown
        }
        if binding.heldModifier != nil { return stroke.modifiers == binding.modifiers }
        // A combination is down while its key is down and exactly its modifiers are held.
        return stroke.phase == .down && stroke.keyCode == binding.keyCode
            && stroke.modifiers == binding.modifiers
    }

    /// The modifiers a held binding is made of, its own key's included.
    private var heldModifiers: Set<HotkeyModifier> {
        binding.modifiers.union(modifiersOfHeldKey)
    }

    /// The modifier a held binding's own key code is, so ⌘ held alone reads as ⌘.
    private var modifiersOfHeldKey: Set<HotkeyModifier> {
        guard let named = HotkeyBinding.modifier(ofKeyCode: binding.keyCode) else { return [] }
        return [named]
    }

    /// Reports only a change, since a flags change says what is held rather than what moved.
    private mutating func settle(_ downNow: Bool) -> HotkeyEvent? {
        edge.flagsChanged(isDownNow: downNow)
    }
}
