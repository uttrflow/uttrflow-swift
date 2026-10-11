import UttrflowContext
import UttrflowCore
import UttrflowPredict
import UttrflowPredictStore

/// Builds one turn's context from the existing window and corpus readers.
@MainActor
enum SuggestionSituationBuilder {
    /// Whether the window around this field is walked, which a terminal's is not since its value already holds the scrollback.
    nonisolated static func walksSurroundings(of snapshot: FocusedFieldSnapshot) -> Bool {
        !TerminalApplications.contains(snapshot.bundleIdentifier)
    }

    /// The text around the field, or nothing where the window is not walked.
    private static func surroundings(
        of snapshot: FocusedFieldSnapshot, cache: SuggestionContextCache,
        readingWindow: @escaping @Sendable () async -> Surroundings?
    ) async -> Surroundings? {
        guard walksSurroundings(of: snapshot) else { return nil }
        return await cache.surroundings(for: SuggestionMoment.windowKey(of: snapshot)) {
            await readingWindow()
        }
    }

    /// Reads what is on screen and what this person wrote here, then maps them with ``SuggestionMoment``.
    static func situation(
        of snapshot: FocusedFieldSnapshot, for query: SuggestionQuery, store: PredictStore,
        cache: SuggestionContextCache, turn: Int,
        readingWindow: @escaping @Sendable () async -> Surroundings?,
        log: @MainActor (Surroundings?, [String], GenerationSituation) -> Void
    ) async -> GenerationSituation {
        // The alternatives pass asks about the same line in the same turn, so it is told what the first pass was.
        if let built = await cache.situation(forTurn: turn) { return built }
        // Neither read needs the other, so the walk and the corpus query run side by side.
        async let walk = surroundings(of: snapshot, cache: cache, readingWindow: readingWindow)
        async let remembered =
            (try? await store.recent(in: query.surface, limit: SuggestionMoment.recentLinesShown)) ?? []
        let around = await walk
        let recent = SuggestionMoment.recentLines(await remembered, typing: query.typed)
        let situation = SuggestionMoment.situation(of: snapshot, surroundings: around, recentLines: recent)
        log(around, recent, situation)
        await cache.remember(situation, forTurn: turn)
        return situation
    }
}
