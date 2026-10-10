// What the recogniser writes for each Markdown command phrase on synthesised speech, scored by the command reader.
public import UttrflowCore

/// One command phrase read by a synthetic voice under one noise level, and the recogniser's text for it.
public struct CommandTake: Sendable, Equatable {
    public let commandID: String
    public let voice: String
    /// Signal-to-noise ratio in dB; infinity is clean audio.
    public let snr: Double
    public let heard: String

    public init(commandID: String, voice: String, snr: Double, heard: String) {
        self.commandID = commandID
        self.voice = voice
        self.snr = snr
        self.heard = heard
    }
}

/// Recall of each command phrase on audio: a take counts when the reader makes the edit the phrase itself makes.
public struct CommandAudioReport: Sendable, Equatable {
    /// One command's takes.
    public struct Row: Sendable, Equatable {
        public let commandID: String
        public let takes: Int
        public let hits: Int
        /// Takes heard as a different command, which would rewrite the selection the wrong way.
        public let misfires: Int

        public var recall: Double { takes == 0 ? 0 : Double(hits) / Double(takes) }
    }

    public let rows: [Row]
    public let missed: [CommandTake]
    public let misfires: [CommandTake]
    /// Every take, and beside it whether it hit, for recall by voice or by noise level.
    public let takes: [CommandTake]
    public let hits: [Bool]

    /// The document and selection every take is read against: one word at a line start in a Markdown file.
    public static let target = AppContext(documentName: "notes.md", selectedText: "Plan", precedingText: "")

    /// Scores every take with `reads`, the edit a command would make or nil when none runs.
    public init(takes: [CommandTake], reads: (String, AppContext) -> String?) {
        let phrases = Dictionary(
            uniqueKeysWithValues: SpokenCommands.markdown.map { ($0.id, $0.words.joined(separator: " ")) })
        var results: [(take: CommandTake, hit: Bool, misfire: Bool)] = []
        for take in takes {
            let wanted = phrases[take.commandID].flatMap { reads($0, Self.target) }
            let made = reads(take.heard, Self.target)
            let hit = made != nil && made == wanted
            results.append((take, hit, made != nil && !hit))
        }
        self.takes = takes
        hits = results.map(\.hit)
        missed = results.filter { !$0.hit }.map(\.take)
        misfires = results.filter(\.misfire).map(\.take)
        var order: [String] = []
        for take in takes where !order.contains(take.commandID) { order.append(take.commandID) }
        rows = order.map { id in
            let mine = results.filter { $0.take.commandID == id }
            return Row(
                commandID: id, takes: mine.count, hits: mine.count(where: \.hit),
                misfires: mine.count(where: \.misfire))
        }
    }

    /// The share of takes that hit, over all of them.
    public var recall: Double { recall { _ in true } }

    /// The share of takes that hit among those `matching` picks, such as one voice or one noise level.
    public func recall(where matching: (CommandTake) -> Bool) -> Double {
        let picked = zip(takes, hits).filter { matching($0.0) }
        return picked.isEmpty ? 0 : Double(picked.count { $0.1 }) / Double(picked.count)
    }

    /// The release gate, held at the last measured run (`Docs/commands.md`): recall never falls, misfires never rise.
    public var passesGate: Bool {
        recall >= Self.recallFloor && misfires.count <= Self.misfireCeiling
    }

    /// The overall recall of the recorded run, 117 of 216 takes; a reader or recogniser change may not lower it.
    public static let recallFloor = 117.0 / 216.0
    /// The misfires of the recorded run; a change may not add one.
    public static let misfireCeiling = 0
}
