/// What one surroundings read may still spend: elements visited, characters gathered, and time.
struct WalkBudget {
    /// Which end of a text is kept when it does not fit: its start, or its end when reading backward.
    enum Cut { case keepStart, keepEnd }

    let maximumElements: Int
    let maximumCharacters: Int
    let deadline: ContinuousClock.Instant
    /// Whether the read's owner still wants it; false once its queue ticket is invalidated.
    let isWanted: @Sendable () -> Bool
    private(set) var visited = 0
    private(set) var gathered = 0

    init(
        deadline: ContinuousClock.Instant, maximumElements: Int = Surroundings.maximumElements,
        maximumCharacters: Int = Surroundings.maximumCharacters,
        isWanted: @escaping @Sendable () -> Bool = { true }
    ) {
        self.deadline = deadline
        self.isWanted = isWanted
        self.maximumElements = maximumElements
        self.maximumCharacters = maximumCharacters
    }

    /// How many characters the read may still take, the separator before them counted.
    var room: Int { maximumCharacters - gathered - (gathered > 0 ? 1 : 0) }

    /// Whether the read has spent its time, its element allowance or its characters, or is unwanted.
    var isExhausted: Bool {
        visited >= maximumElements || room <= 0 || ContinuousClock.now >= deadline || !isWanted()
    }

    /// How many more elements a visit could still reach, which bounds how many are worth queueing.
    var remainingVisits: Int { max(0, maximumElements - visited) }

    /// Counts one element visited.
    mutating func spendVisit() { visited += 1 }

    /// As much of the text as still fits, cut on the side `cut` drops, and charged with its separator.
    mutating func take(_ text: String, _ cut: Cut) -> String {
        let room = room
        let piece =
            text.count <= room ? text : String(cut == .keepEnd ? text.suffix(room) : text.prefix(room))
        gathered += piece.count + (gathered > 0 ? 1 : 0)
        return piece
    }
}
