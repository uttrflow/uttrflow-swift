// A ContextEngine that reports whatever screen a test scripts.
public import UttrflowCore

/// A ``ContextEngine`` that returns a fixed context.
public actor FakeContextEngine: ContextEngine {
    public let calls = CallLog<Void>()

    private var context: AppContext
    private var names: [String]
    /// How many times the wider walk was asked for names.
    public let nameCalls = CallLog<Void>()

    public init(context: AppContext = .unknown, onScreenNames: [String] = []) {
        self.context = context
        self.names = onScreenNames
    }

    public func onScreenNames() async -> [String] {
        await nameCalls.append(())
        return names
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
            followingText: insertion.followingText,
            isSecure: context.isSecure
        )
    }
}
