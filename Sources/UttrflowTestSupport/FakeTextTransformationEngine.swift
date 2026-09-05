public import UttrflowCore

/// A ``TextTransformationEngine`` with scriptable availability and output.
///
/// Availability is scriptable because routing around an engine that cannot handle a
/// language is a behaviour the pipeline must be tested for, not an edge case.
public actor FakeTextTransformationEngine: TextTransformationEngine {
    public let kind: TransformerKind
    public let availabilityCalls = CallLog<TransformationRequest>()
    public let transformCalls = CallLog<TransformationRequest>()
    public let warmCalls = CallLog<Void>()

    private var availability: TransformerAvailability
    private var transformOutcome: ScriptedOutcome<TransformationResult, TransformationError>

    public init(
        kind: TransformerKind = .foundationModels,
        availability: TransformerAvailability = .available,
        transformOutcome: ScriptedOutcome<TransformationResult, TransformationError>? = nil
    ) {
        self.kind = kind
        self.availability = availability
        self.transformOutcome =
            transformOutcome
            ?? .success(TransformationResult(text: "transformed", producedBy: kind))
    }

    public func availability(for request: TransformationRequest) async -> TransformerAvailability {
        await availabilityCalls.append(request)
        return availability
    }

    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        await transformCalls.append(request)
        return try transformOutcome.resolve()
    }

    public func warm() async {
        await warmCalls.append(())
    }

    // MARK: Scripting

    public func setAvailability(_ availability: TransformerAvailability) {
        self.availability = availability
    }

    public func setTransformOutcome(
        _ outcome: ScriptedOutcome<TransformationResult, TransformationError>
    ) {
        transformOutcome = outcome
    }
}
