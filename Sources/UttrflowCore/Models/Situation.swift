/// What the screen said at the moment the key went down, read once and handed to every stage.
public struct Situation: Sendable, Equatable {
    public let app: AppContext
    public let insertion: InsertionPoint
    public let destination: Destination
    public let intent: WritingIntent
    /// How the person writes numbers.
    public let numberStyle: NumberStyle

    public init(
        app: AppContext, insertion: InsertionPoint, destination: Destination,
        numberStyle: NumberStyle = .standard
    ) {
        self.app = app
        self.insertion = insertion
        self.destination = destination
        self.intent = WritingIntent(app: app, insertion: insertion)
        self.numberStyle = numberStyle
    }

    /// The grouping written here: none where the place parses its digits, otherwise the person's own.
    public func digits(for formatter: DestinationFormatter) -> DigitGrouping {
        formatter.digits == .none ? .none : numberStyle.grouping
    }

    /// The situation when the screen says nothing at all.
    public static let unknown = Situation(app: .unknown, insertion: .unknown, destination: .plain)
}

/// Turns what was read off the screen into a situation, by the user's overrides and the classifier's table.
public enum SituationResolver {
    public static func resolve(
        app: AppContext, insertion: InsertionPoint,
        rules: [DestinationRule] = DestinationRules.standard,
        overrides: DestinationOverrides = .none
    ) -> Situation {
        Situation(
            app: app, insertion: insertion,
            destination: DestinationClassifier.classify(app, rules: rules, overrides: overrides))
    }

    /// The situation a context read carries, together with its own caret text.
    public static func resolve(
        from app: AppContext, overrides: DestinationOverrides = .none
    ) -> Situation {
        resolve(app: app, insertion: app.insertionPoint, overrides: overrides)
    }
}

extension AppContext {
    /// The caret as the context read found it.
    public var insertionPoint: InsertionPoint {
        InsertionPoint(precedingText: precedingText, followingText: followingText)
    }

    /// What recognition is conditioned on before the caret: never from a secure field, never stored past the dictation.
    public var recognitionContext: String? { isSecure ? nil : insertionPoint.recognitionContext }
}
