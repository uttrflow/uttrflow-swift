// The check that refuses a calibration whose value, or a layer beneath it, moved since it was fitted.

/// Why each calibration in a chain is out of date against the layers as they are now.
public enum CalibrationGraph {
    public typealias Layer = CalibrationRecord.Layer

    /// One reason a calibration must be fitted again before it ships.
    public enum Finding: Sendable, Equatable {
        /// The value in the code is not the value the record says was fitted.
        case valueMoved(Layer, recorded: String, live: String?)
        /// A layer the value reads has a different revision from the one it was fitted under.
        case upstreamMoved(Layer, upstream: Layer, recorded: String, live: String?)
        /// A calibration the value reads is itself out of date, so this one is too.
        case upstreamStale(Layer, upstream: Layer)
        /// The value claims to read a layer that is fitted after it.
        case fittedOutOfOrder(Layer, upstream: Layer)
    }

    /// Every finding for `records` against `live`, each layer's revision now; empty means all may ship.
    public static func findings(
        _ records: [CalibrationRecord], live: [Layer: String]
    ) -> [Finding] {
        var stale: Set<Layer> = []
        var found: [Finding] = []
        for record in records.sorted(by: { $0.layer < $1.layer }) {
            let own = findings(for: record, live: live, stale: stale)
            if !own.isEmpty { stale.insert(record.layer) }
            found += own
        }
        return found
    }

    /// The findings for one record, given which earlier calibrations are already out of date.
    static func findings(
        for record: CalibrationRecord, live: [Layer: String],
        stale: Set<Layer>
    ) -> [Finding] {
        var found: [Finding] = []
        if live[record.layer] != record.value {
            found.append(.valueMoved(record.layer, recorded: record.value, live: live[record.layer]))
        }
        for (upstream, recorded) in record.fittedUnder.sorted(by: { $0.key < $1.key }) {
            if upstream >= record.layer {
                found.append(.fittedOutOfOrder(record.layer, upstream: upstream))
            } else if live[upstream] != recorded {
                let moved = Finding.upstreamMoved(
                    record.layer, upstream: upstream, recorded: recorded, live: live[upstream])
                found.append(moved)
            } else if stale.contains(upstream) {
                found.append(.upstreamStale(record.layer, upstream: upstream))
            }
        }
        return found
    }
}
