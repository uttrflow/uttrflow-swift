/// What the surface should draw, and nothing about where.
public enum Suggestion: Sendable, Equatable {
    /// Nothing is drawn, which is the most common answer.
    case silent
    /// One candidate is clearly ahead, so the line finishes itself.
    case certain(String)
    /// Several are close, so the leader is shown inline with the rest listed under it.
    case choice(leader: String, others: [String])
    /// The user pressed escape, so only the dot remains.
    case minimised

    /// The whole line Tab would leave behind, or `nil` when nothing is on offer.
    public var accepting: String? {
        switch self {
        case .certain(let text): text
        case .choice(let leader, _): leader
        case .silent, .minimised: nil
        }
    }

    /// The same answer with everything short of certainty removed, which is what quiet mode draws.
    public var certainOnly: Suggestion {
        if case .choice = self { .silent } else { self }
    }

    /// What Tab does to a field holding `typed`, which is the one answer the surface also draws.
    public func edit(after typed: String) -> Acceptance.Edit? {
        guard let accepting else { return nil }
        return Acceptance.edit(accepting: accepting, after: typed)
    }

    /// Removes the part of a completion's insertion that duplicates closing punctuation after the caret.
    public func trimmed(after typed: String, matching closers: String) -> Suggestion {
        func trim(_ text: String) -> String {
            guard let edit = Acceptance.edit(accepting: text, after: typed) else { return text }
            let inserted = Array(edit.inserted)
            let following = Array(closers)
            let limit = min(inserted.count, following.count)
            guard limit > 0 else { return text }
            let overlap =
                (1...limit).reversed().first { count in
                    inserted.suffix(count).elementsEqual(following.prefix(count))
                } ?? 0
            guard overlap > 0 else { return text }
            return edit.applied(to: typed).dropLast(overlap).description
        }

        switch self {
        case .certain(let text): return .certain(trim(text))
        case .choice(let leader, let others): return .choice(leader: trim(leader), others: others.map(trim))
        case .silent: return .silent
        case .minimised: return .minimised
        }
    }
}

/// What the shared generated-line gate decides the app and bake-off may draw.
public enum GeneratedSuggestionDecision: Sendable, Equatable {
    /// No generated line can extend the typed text.
    case noCandidate
    /// Candidates extend the typed text, but none may be drawn at the scores given.
    case unsure
    /// One candidate clears the certainty floor.
    case certain(String)
    /// The leader and its alternatives clear the choice floor.
    case choice(leader: String, others: [String])
}
