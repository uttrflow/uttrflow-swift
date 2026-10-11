// Where the capture path sends a finished value, and the corpus standing behind it.
public import UttrflowPredict
public import UttrflowPredictStore

public import struct Foundation.Date

/// Where finished values go, named as a protocol so the capture path can be tested without a database.
public protocol CaptureSink: Sendable {
    /// Records a value the user entered, what it followed, and how it reached the field.
    func record(
        _ text: String, in surface: Surface, after previous: String?, as origin: LineOrigin, at moment: Date
    ) async throws

    /// Marks an entry wrong and points at what replaces it, so it is never proposed again.
    func supersede(_ text: String, with replacement: String, in surface: Surface) async throws

    /// Counts one acceptance of a line already recorded, which the ranking weighs.
    func recordAccepted(_ text: String, in surface: Surface) async throws

    /// Takes back one acceptance the person undid, with the use it added.
    func retractAcceptance(_ text: String, in surface: Surface) async throws

    /// Hears one edit the person made inside inserted text, for the dictation side to learn from.
    func recordEditedSpan(_ edit: EditedSpan, in surface: Surface) async throws
}

extension CaptureSink {
    /// A sink that keeps no acceptance counts is not wrong, only less informed.
    public func recordAccepted(_ text: String, in surface: Surface) async throws {}

    /// A sink that keeps no acceptance counts has nothing to take back.
    public func retractAcceptance(_ text: String, in surface: Surface) async throws {}

    /// Suggestions learn only typed lines, so a sink for them ignores edits inside inserted text.
    public func recordEditedSpan(_ edit: EditedSpan, in surface: Surface) async throws {}
}

/// The corpus on disk is the sink the app uses; nothing here is added to it.
extension PredictStore: CaptureSink {}
