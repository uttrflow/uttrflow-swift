// A ContextEngine that reports whatever screen a test scripts.
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
}
