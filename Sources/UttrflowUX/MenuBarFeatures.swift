/// Which of the three are on, held as three answers so switching one cannot move another.
public struct MenuBarFeatures: Sendable, Equatable {
    public var dictation: Bool
    public var clipboard: Bool
    /// Off to begin with, the same as the setting it stands for.
    public var suggestions: Bool
    /// What keeps AI suggestions off while their switch is on; nil when nothing does.
    var suggestionHold: SuggestionHold?

    public init(dictation: Bool = true, clipboard: Bool = true, suggestions: Bool = false) {
        self.dictation = dictation
        self.clipboard = clipboard
        self.suggestions = suggestions
    }

    public func isOn(_ feature: MenuBarFeature) -> Bool {
        switch feature {
        case .dictation: dictation
        case .clipboard: clipboard
        case .suggestions: suggestions
        }
    }

    /// Answers a copy with one switch moved, which is the whole of the independence promise.
    public func setting(_ feature: MenuBarFeature, isOn: Bool) -> MenuBarFeatures {
        var updated = self
        switch feature {
        case .dictation: updated.dictation = isOn
        case .clipboard: updated.clipboard = isOn
        case .suggestions:
            updated.suggestions = isOn
            updated.suggestionHold = nil
        }
        return updated
    }
}

/// Why AI suggestions are off with their switch on, which decides what the unticked menu item does.
enum SuggestionHold: Sendable, Equatable {
    /// The pause, and nothing else.
    case paused
    /// The person turned suggestions off in this application, with or without a pause as well.
    case turnedOffHere(application: String, isPaused: Bool)
    /// A shipped editor with suggestions of its own, which one menu click should not opt in.
    case offByDefault
    /// A shipped application that holds private information, which one menu click should not opt in.
    case offAsPrivate
}
