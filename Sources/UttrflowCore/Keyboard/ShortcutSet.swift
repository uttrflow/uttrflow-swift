// Every shortcut the user has, as one value. See `Docs/shortcuts.md`.

/// The bindings each action answers to, in the order the user added them.
public struct ShortcutSet: Sendable, Equatable {
    /// Only bindings that could actually fire; the initialiser drops the rest.
    private var bound: [ShortcutAction: [HotkeyBinding]]

    /// Keeps the deliverable bindings and drops the rest, so nothing unusable is ever held.
    public init(_ bound: [ShortcutAction: [HotkeyBinding]] = [:]) {
        self.bound = bound.compactMapValues { bindings in
            let usable = bindings.filter(\.isDeliverable)
            return usable.isEmpty ? nil : usable
        }
    }

    /// What the product ships with; the shortcuts screen offers this back as "reset".
    public static let `default` = ShortcutSet([
        .dictate: [.controlOptionHold],
        .clipboard: [.shiftCommandV],
        .pasteLastTranscript: [.controlCommandV],
        .copyLastTranscript: [.controlCommandC],
        .editCommand: [.controlShiftHold],
    ])

    /// The defaults with ⌥Space for dictation, which an install onboarded before ⌃⌥ held keeps.
    public static let earlierDefault: ShortcutSet = {
        var set = ShortcutSet.default
        set.replace(at: 0, with: .optionSpace, for: .dictate)
        return set
    }()

    /// Every binding for one action, which is empty when the user has bound none.
    public func bindings(for action: ShortcutAction) -> [HotkeyBinding] {
        bound[action] ?? []
    }

    /// The binding an action leads with, or nothing when it has none.
    public func first(for action: ShortcutAction) -> HotkeyBinding? {
        bound[action]?.first
    }

    /// Whether anything at all is bound to an action.
    public func isBound(_ action: ShortcutAction) -> Bool {
        !bindings(for: action).isEmpty
    }

    /// Adds a way into an action, ignoring one it already answers to.
    public mutating func add(_ binding: HotkeyBinding, to action: ShortcutAction) {
        guard binding.isDeliverable else { return }
        var bindings = bindings(for: action)
        guard !bindings.contains(binding) else { return }
        bindings.append(binding)
        bound[action] = bindings
    }

    /// Puts one binding in another's place, which is what changing a row does.
    public mutating func replace(
        at index: Int, with binding: HotkeyBinding, for action: ShortcutAction
    ) {
        guard binding.isDeliverable else { return }
        var bindings = bindings(for: action)
        guard bindings.indices.contains(index) else { return add(binding, to: action) }
        bindings[index] = binding
        bound[action] = bindings
    }

    /// Takes a way in away; the last one may go, since an action with none is allowed.
    public mutating func remove(at index: Int, from action: ShortcutAction) {
        var bindings = bindings(for: action)
        guard bindings.indices.contains(index) else { return }
        bindings.remove(at: index)
        bound[action] = bindings.isEmpty ? nil : bindings
    }

    /// The action already answering to these keys, so a clash can name what holds them.
    public func action(holding binding: HotkeyBinding, besides action: ShortcutAction?) -> ShortcutAction? {
        for candidate in ShortcutAction.allCases where candidate != action {
            if bindings(for: candidate).contains(binding) { return candidate }
        }
        return nil
    }
}

// A forgiving shape on disk: unknown actions and unusable bindings are dropped, not fatal.
extension ShortcutSet: Codable {
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: ShortcutSetCodingKey.self) else {
            self.init()
            return
        }
        var bound: [ShortcutAction: [HotkeyBinding]] = [:]
        for key in container.allKeys {
            guard let action = ShortcutAction(rawValue: key.stringValue),
                var values = try? container.nestedUnkeyedContainer(forKey: key)
            else { continue }
            var bindings: [HotkeyBinding] = []
            while !values.isAtEnd {
                guard let value = try? values.superDecoder() else { break }
                if let binding = try? HotkeyBinding(from: value) { bindings.append(binding) }
            }
            bound[action] = bindings
        }
        self.init(bound)
        for action in Self.boundOnlyToBareModifiers(in: bound) { returnToDefault(action) }
    }

    /// The actions a stored set bound to nothing but a modifier held alone, which this build no longer accepts.
    public static func boundOnlyToBareModifiers(
        in bound: [ShortcutAction: [HotkeyBinding]]
    ) -> Set<ShortcutAction> {
        Set(bound.filter { !$0.value.isEmpty && $0.value.allSatisfy(\.isBareModifier) }.keys)
    }

    /// Gives an action its shipped shortcut back, unless another action has since taken those keys.
    public mutating func returnToDefault(_ action: ShortcutAction) {
        for binding in Self.default.bindings(for: action)
        where self.action(holding: binding, besides: action) == nil {
            add(binding, to: action)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        var stored: [String: [HotkeyBinding]] = [:]
        for (action, bindings) in bound { stored[action.rawValue] = bindings }
        try container.encode(stored)
    }
}

private struct ShortcutSetCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
