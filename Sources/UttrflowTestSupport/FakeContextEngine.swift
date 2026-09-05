public import UttrflowCore

/// A ``ContextEngine`` that returns a fixed context.
public actor FakeContextEngine: ContextEngine {
    public let calls = CallLog<Void>()

    private var context: AppContext

    public init(context: AppContext = .unknown) {
        self.context = context
    }

    public func currentContext() async -> AppContext {
        await calls.append(())
        return context
    }

    public func setContext(_ context: AppContext) {
        self.context = context
    }

    /// Scripts what sits at the caret, keeping the rest of the context as it was.
    public func setInsertionPoint(_ insertion: InsertionPoint) {
        context = AppContext(
            applicationName: context.applicationName,
            bundleIdentifier: context.bundleIdentifier,
            documentName: context.documentName,
            selectedText: context.selectedText,
            precedingText: insertion.precedingText,
            followingText: insertion.followingText
        )
    }
}
