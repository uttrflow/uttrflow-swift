import UttrflowPredict
import UttrflowTestSupport

@testable import UttrflowPredictStore

extension PredictStore {
    /// Reads legacy rows through the actor-owned connection, including encrypted fixtures.
    func legacySuccessors(
        for surface: Surface, after previous: String
    ) throws(PredictStoreError) -> [Candidate] {
        try database.rows(
            LegacySuccessions.query,
            { LegacySuccessions.bind($0, surface: surface, previous: Spelling.canonical(previous)) },
            LegacySuccessions.read)
    }
}
