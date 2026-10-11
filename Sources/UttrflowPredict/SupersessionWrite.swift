/// The corpus change derived from a verdict that may make its refusal durable.
enum SupersessionWrite: Sendable {
    case supersede(String, String)
    case reject(String)

    var candidate: String {
        switch self {
        case .supersede(let text, _), .reject(let text): text
        }
    }
}
