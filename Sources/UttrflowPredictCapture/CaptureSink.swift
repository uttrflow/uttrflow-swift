public import UttrflowPredict
public import UttrflowPredictStore

public import struct Foundation.Date

/// Where finished values go, named as a protocol so the capture path can be tested without a database.
public protocol CaptureSink: Sendable {
    /// Records a value the user finished entering, and what it followed.
    func record(
        _ text: String, in surface: Surface, after previous: String?, selfSourced: Bool,
        at moment: Date
    ) async throws

    /// Marks an entry wrong and points at what replaces it, so it is never proposed again.
    func supersede(_ text: String, with replacement: String, in surface: Surface) async throws

    /// Counts one acceptance of a line already recorded, which the ranking weighs.
    func recordAccepted(_ text: String, in surface: Surface) async throws
}

extension CaptureSink {
    /// A sink that keeps no acceptance counts is not wrong, only less informed.
    public func recordAccepted(_ text: String, in surface: Surface) async throws {}
}

/// The corpus on disk is the sink the app uses; nothing here is added to it.
extension PredictStore: CaptureSink {}
