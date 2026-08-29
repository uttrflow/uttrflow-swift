/// One utterance the performance profile puts through the pipeline.
///
/// Deliberately not an ``EvaluationCase``: those exist to be scored, carry a reference
/// transcript, and are all one sentence long. These exist to be *timed*, and the only
/// property that matters is how long they take to say. Sharing the type would have meant
/// a `expected` field nothing reads and a corpus nobody could lengthen without breaking
/// the quality numbers.
public struct ProfilePassage: Sendable, Equatable, Identifiable {
    /// The three utterance lengths a dictation tool has to be honest about.
    ///
    /// Three rather than two, because two points cannot show a bend: linear and
    /// super-linear cost look identical until there is a third length to compare the
    /// gaps between.
    public enum Length: String, Sendable, Equatable, CaseIterable, Codable {
        /// A sentence — the overwhelming majority of real dictations.
        case short
        /// A paragraph, which is what the product is actually sold on.
        case medium
        /// A minute of speech, near the edge of what anyone dictates in one breath.
        case long

        /// Roughly how many seconds of speech this length stands for.
        ///
        /// A target, not a measurement: what a synthesiser actually produces is timed
        /// from the audio file and reported instead of this.
        public var targetSeconds: Double {
            switch self {
            case .short: 3
            case .medium: 15
            case .long: 60
            }
        }
    }

    public let length: Length
    /// What is spoken. Read aloud by a synthesiser rather than a person, so that
    /// re-running the profile on another Mac compares two machines and not two takes.
    public let text: String

    public var id: String { length.rawValue }

    public init(length: Length, text: String) {
        self.length = length
        self.text = text
    }
}

/// One passage of each length, with the audio it produced.
///
/// Kept apart from ``ProfilePassage`` because the duration is a property of the
/// recording, not of the words: the same passage read by a different voice is a
/// different number of seconds, and every cost-per-second figure in the report divides
/// by the one that was actually spoken.
public struct ProfileRecording: Sendable, Equatable {
    public let passage: ProfilePassage
    public let audioSeconds: Double

    public init(passage: ProfilePassage, audioSeconds: Double) {
        self.passage = passage
        self.audioSeconds = audioSeconds
    }
}

/// The passages the performance profile speaks.
///
/// They are ordinary work dictation — fillers, a restart, a port number, a version
/// string, an Indian name — because a profile run on clean read-aloud prose measures a
/// recogniser doing an easier job than the product's.
public enum ProfileCorpus {
    public static let short = ProfilePassage(
        length: .short,
        text: "Send Priya the deck before four, and say the numbers are final."
    )

    public static let medium = ProfilePassage(
        length: .medium,
        text: """
            So, um, I need you to look at the deployment again. The staging box is on \
            port eight thousand and eighty, not eight thousand, and the build is version \
            two point four point one. Priya said she would, uh, she would sign it off \
            tomorrow morning.
            """
    )

    public static let long = ProfilePassage(
        length: .long,
        text: """
            Right, so here is where we landed after the review this morning. The \
            migration is going ahead, but not this week. We found that the indexing job \
            takes about forty minutes on the production copy, which is, um, roughly four \
            times what we measured on staging, and nobody could explain the gap until \
            Arjun noticed the staging snapshot was three months old. So the first thing \
            is to refresh that snapshot. Second, the retry logic in the ingest worker \
            needs a cap. At the moment a poisoned message will spin forever, and it took \
            down the queue on Tuesday. I want an exponential backoff with a ceiling of, \
            let us say, five attempts, and then it goes to the dead letter queue where \
            somebody can actually look at it. Third, and this is the one I care about \
            most, we still have no alerting on the disk usage of the primary. It filled \
            up in April and we only found out because a customer emailed us about it. \
            Priya is going to write that one up properly, with thresholds at eighty and \
            ninety percent. Let us reconvene on Thursday at eleven.
            """
    )

    /// Shortest first, so a report reads in the order the cost grows.
    public static let all: [ProfilePassage] = [short, medium, long]

    public static func passage(_ length: ProfilePassage.Length) -> ProfilePassage {
        switch length {
        case .short: short
        case .medium: medium
        case .long: long
        }
    }
}
