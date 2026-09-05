/// The small words a phrase is built from, which carry structure rather than what was said.
public enum FunctionWords {
    /// Whether the word is one of the small words, apostrophes and case aside.
    public static func holds(_ word: String) -> Bool {
        all.contains(word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'"))
    }

    /// Whether the word carries meaning, so a restatement may be anchored on it or replace it.
    public static func isContent(_ word: String) -> Bool { !word.isEmpty && !holds(word) }

    /// Articles, determiners, prepositions, conjunctions, auxiliaries and pronouns; `MeaningPreservationGuard` keeps its own copy until a follow-up shares this one.
    public static let all: Set<String> = [
        "a", "an", "the",
        "of", "in", "on", "at", "to", "for", "with", "by", "from", "about", "into", "onto", "over",
        "under", "after", "before", "between", "through", "during", "against", "among", "without",
        "within", "along", "across", "behind", "beyond", "near", "up", "down", "off", "out", "around",
        "past", "since", "until", "till", "upon", "toward", "towards", "per",
        "and", "or", "but", "nor", "so", "yet", "because", "although", "though", "while", "if",
        "unless", "than", "whether", "that", "as", "when", "where", "once",
        "am", "is", "are", "was", "were", "be", "been", "being", "do", "does", "did", "have", "has",
        "had", "having", "will", "would", "shall", "should", "can", "could", "may", "might", "must",
        "ought", "not",
        "don't", "doesn't", "didn't", "won't", "wouldn't", "can't", "couldn't", "shouldn't", "isn't",
        "aren't", "wasn't", "weren't", "hasn't", "haven't", "hadn't", "mustn't", "ain't",
        "dont", "doesnt", "didnt", "wont", "wouldnt", "cant", "couldnt", "shouldnt", "isnt", "arent",
        "wasnt", "werent", "hasnt", "havent", "hadnt", "aint",
        "i'll", "i'm", "i've", "i'd", "he'll", "she'll", "we'll", "they'll", "you'll", "it'll",
        "it's", "that's", "there's", "here's", "what's", "who's", "let's", "you're", "we're",
        "they're", "you've", "we've", "they've", "you'd", "we'd", "they'd", "he'd", "she'd",
        "im", "ive", "youre", "theyre", "youve", "weve", "theyve", "thats", "theres",
        "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your",
        "his", "its", "our", "their", "mine", "yours", "hers", "ours", "theirs", "this", "these",
        "those", "there", "who", "whom", "whose", "which", "what", "myself", "yourself", "himself",
        "herself", "itself", "ourselves", "yourselves", "themselves",
    ]

    /// The prepositions a repeated frame may open on; "to" is left out, being the mark of an infinitive.
    public static let prepositions: Set<String> = [
        "of", "in", "on", "at", "for", "with", "by", "from", "about", "into", "onto", "over",
        "under", "after", "before", "between", "during", "among", "without", "within", "along",
        "across", "behind", "beyond", "near", "past", "since", "until", "upon", "toward", "towards",
        "as", "per",
    ]

    /// The words that pair with themselves in a fixed comparison, so one alone never frames a correction.
    public static let correlatives: Set<String> = ["as"]

    /// The subject pronouns and auxiliaries whose presence makes a repeated frame a fresh clause.
    public static let clauseOpeners: Set<String> = [
        "i", "you", "he", "she", "it", "we", "they", "there", "who", "that", "which",
        "am", "is", "are", "was", "were", "be", "been", "being", "do", "does", "did", "have", "has",
        "had", "having", "will", "would", "shall", "should", "can", "could", "may", "might", "must",
    ]
}
