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

    /// What Tab does to a field holding `typed`, which is the one answer the surface also draws.
    public func edit(after typed: String) -> Acceptance.Edit? {
        guard let accepting else { return nil }
        return Acceptance.edit(accepting: accepting, after: typed)
    }
}
