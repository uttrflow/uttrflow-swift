/// What the screen said at the moment the key went down, read once and handed to every stage.
public struct Situation: Sendable, Equatable {
    public let app: AppContext
    public let insertion: InsertionPoint
    public let destination: Destination

    public init(app: AppContext, insertion: InsertionPoint, destination: Destination) {
        self.app = app
        self.insertion = insertion
        self.destination = destination
    }

    /// The situation when the screen says nothing at all.
    public static let unknown = Situation(app: .unknown, insertion: .unknown, destination: .plain)
}

/// Turns what was read off the screen into a situation, by the classifier's table alone.
public enum SituationResolver {
    public static func resolve(
        app: AppContext, insertion: InsertionPoint, rules: [DestinationRule] = DestinationRules.standard
    ) -> Situation {
        Situation(
            app: app, insertion: insertion, destination: DestinationClassifier.classify(app, rules: rules))
    }

    /// The situation a context read carries, together with its own caret text.
    public static func resolve(from app: AppContext) -> Situation {
        resolve(app: app, insertion: app.insertionPoint)
    }
}

extension AppContext {
    /// The caret as the context read found it.
    public var insertionPoint: InsertionPoint {
        InsertionPoint(precedingText: precedingText, followingText: followingText)
    }
}
