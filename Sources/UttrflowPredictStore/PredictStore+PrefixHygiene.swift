extension PredictStore {
    /// Whether a longer non-superseded line the user entered begins with this one, making it a fragment.
    func isFragmentOfLongerEntry(
        surfaceIdentifier id: Int64, text: String
    ) throws(PredictStoreError) -> Bool {
        let lowered = text.lowercased()
        let length = Int64(lowered.unicodeScalars.count)
        let found = try database.rows(
            """
            SELECT 1 FROM entry
            WHERE surface_id = ? AND superseded_by IS NULL
              AND length(text_lower) > ? AND substr(text_lower, 1, ?) = ?
            LIMIT 1
            """,
            {
                $0.bind(1, id)
                $0.bind(2, length)
                $0.bind(3, length)
                $0.bind(4, lowered)
            }
        ) { $0.integer(0) }
        return !found.isEmpty
    }

    /// Retires every shorter unfinished entry that this value begins with, pointing each at this value.
    func supersedeFragments(
        surfaceIdentifier id: Int64, of text: String
    ) throws(PredictStoreError) {
        let lowered = text.lowercased()
        let fragments = try database.rows(
            """
            SELECT text FROM entry
            WHERE surface_id = ? AND superseded_by IS NULL AND finished = 0 AND text <> ?
              AND length(text_lower) < ? AND text_lower = substr(?, 1, length(text_lower))
            """,
            {
                $0.bind(1, id)
                $0.bind(2, text)
                $0.bind(3, Int64(lowered.unicodeScalars.count))
                $0.bind(4, lowered)
            }
        ) { $0.text(0) }
        for fragment in fragments {
            try markSuperseded(fragment, by: text, surfaceIdentifier: id)
        }
    }

    /// Points one entry at what replaces it, which is how a correction and a fragment are both retired.
    func markSuperseded(
        _ text: String, by replacement: String, surfaceIdentifier id: Int64
    ) throws(PredictStoreError) {
        try database.run(
            "UPDATE entry SET superseded_by = ? WHERE surface_id = ? AND text = ?",
            {
                $0.bind(1, replacement)
                $0.bind(2, id)
                $0.bind(3, text)
            })
    }

    /// Whether this entry is a line the person finished, which nothing but a correction retires.
    func isFinished(entry id: Int64) throws(PredictStoreError) -> Bool {
        try !database.rows("SELECT 1 FROM entry WHERE id = ? AND finished = 1", { $0.bind(1, id) }) {
            $0.integer(0)
        }.isEmpty
    }

    /// Whether this folder holds the exact line as one the person finished.
    func holdsFinishedLine(_ text: String, surfaceIdentifier id: Int64) throws(PredictStoreError) -> Bool {
        try !database.rows(
            "SELECT 1 FROM entry WHERE surface_id = ? AND text = ? AND finished = 1",
            {
                $0.bind(1, id)
                $0.bind(2, text)
            }
        ) { $0.integer(0) }.isEmpty
    }
}
