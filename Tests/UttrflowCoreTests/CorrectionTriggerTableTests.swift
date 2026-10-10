import Testing

@testable import UttrflowCore

/// One spoken sentence holding a trigger phrase, and what it reads as once the correction is applied, or nil when it is plain speech.
struct TriggerCase: Sendable, CustomTestStringConvertible {
    let phrase: String
    let spoken: String
    let kept: String?

    var testDescription: String { spoken }
}

/// The words left once the first run of `phrase` in `spoken` takes back what it announces, or nil when it takes nothing.
private func applied(_ phrase: String, in spoken: String) -> String?? {
    let draft = Draft(text: spoken)
    let live = draft.presentIndices
    let keys = live.map { draft.shape(at: $0).key }
    let words = phrase.split(separator: " ").map(String.init)
    guard
        let trigger = (0...(keys.count - words.count)).first(where: {
            Array(keys[$0..<$0 + words.count]) == words
        })
    else { return .none }
    let restart = trigger + Restatement.triggerRun(at: trigger, in: live, of: draft)
    guard restart > trigger, restart < live.count,
        let start = Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft)
    else { return .some(nil) }
    return .some((keys[..<start] + keys[restart...]).joined(separator: " "))
}

private func corrected(_ phrase: String, _ spoken: String, _ kept: String) -> TriggerCase {
    TriggerCase(phrase: phrase, spoken: spoken, kept: kept)
}

private func plain(_ phrase: String, _ spoken: String) -> TriggerCase {
    TriggerCase(phrase: phrase, spoken: spoken, kept: nil)
}

/// Hinglish speech with a correction in it, every one of which must take back its first half.
fileprivate let hinglishCorrections: [TriggerCase] = [
    corrected("nahi nahi", "kal teen baje nahi nahi chaar baje milte hain", "kal chaar baje milte hain"),
    corrected("nahi nahi", "do kilo nahi nahi paanch kilo aata lana", "paanch kilo aata lana"),
    corrected("nahi nahi", "saat log nahi nahi aath log aayenge", "aath log aayenge"),
    corrected("nahi nahi", "train das baje nahi nahi gyarah baje hai", "train gyarah baje hai"),
    corrected("nahi nahi", "room number 12 nahi nahi 14 hai", "room number 14 hai"),
    corrected("nahi nahi", "bees rupaye nahi nahi pachaas", "pachaas"),
    corrected("mera matlab", "meeting teen baje, mera matlab, chaar baje hai", "meeting chaar baje hai"),
    corrected("mera matlab", "panch din, mera matlab, saat din lagenge", "saat din lagenge"),
    corrected("mera matlab", "das minute, mera matlab, bees minute ruko", "bees minute ruko"),
    corrected("mera matlab", "order 3 packet, mera matlab, 5 packet ka hai", "order 5 packet ka hai"),
    corrected("no sorry", "kal paanch baje no sorry six baje aana", "kal six baje aana"),
    corrected("no sorry", "budget ten lakh no sorry twelve lakh hai", "budget twelve lakh hai"),
    corrected("no wait", "flight monday ko hai no wait tuesday ko hai", "flight tuesday ko hai"),
    corrected("no wait", "chai do cup no wait three cup", "chai three cup"),
    corrected(
        "wait sorry", "file ka naam report hai wait sorry ka naam summary hai", "file ka naam summary hai"),
    corrected("i mean", "deadline friday hai i mean deadline monday hai", "deadline monday hai"),
    corrected("i mean", "usko ten bajey i mean eleven bajey call karo", "usko eleven bajey call karo"),
    corrected("or rather", "chai or rather coffee pi lete hain", "coffee pi lete hain"),
    corrected("scratch that", "rahul ko bhejo scratch that rahul ko mat bhejo", "rahul ko mat bhejo"),
    corrected("strike that", "red wala lo strike that blue wala lo", "blue wala lo"),
    corrected("correction", "total four hundred correction five hundred hai", "total five hundred hai"),
    corrected("actually make it", "do pizza actually make it three pizza", "three pizza"),
    corrected("actually make that", "chai do cup actually make that three cup", "chai three cup"),
    corrected("no make it", "do kilo no make it teen kilo aata lana", "teen kilo aata lana"),
    corrected("actually", "price twenty, actually thirty hai", "price thirty hai"),
    corrected("sorry", "kal ki meeting sorry parso ki meeting cancel hai", "parso ki meeting cancel hai"),
    corrected("sorry", "nine baje sorry ten baje aao", "ten baje aao"),
    corrected("no", "station tak nine, no ten minute lagenge", "station tak ten minute lagenge"),
    corrected("never mind", "usko email karo never mind usko call karo", "usko call karo"),
    corrected(
        "no sorry", "hall mein fifty kursi no sorry sixty kursi chahiye", "hall mein sixty kursi chahiye"),
    corrected(
        "i mean", "ghar ka rent twenty i mean twenty five hazaar hai", "ghar ka rent twenty five hazaar hai"),
    corrected("no wait", "bus number forty no wait forty two pakdo", "bus number forty two pakdo"),
    corrected("galat bola", "paanch baje galat bola chhe baje aana", "chhe baje aana"),
    corrected("galat bola", "teen kilo galat bola chaar kilo chawal lao", "chaar kilo chawal lao"),
    corrected("matlab", "do din, matlab, teen din lagenge", "teen din lagenge"),
    corrected("matlab", "saat baje, matlab, aath baje aao", "aath baje aao"),
    corrected("nahi", "teen baje, nahi, chaar baje milte hain", "chaar baje milte hain"),
    corrected("nahi", "do kilo nahi, teen kilo chini lao", "teen kilo chini lao"),
    corrected("sorry sorry", "paanch baje sorry sorry chhe baje aana", "chhe baje aana"),
    corrected("sorry sorry", "blue wali shirt sorry sorry red wali shirt lao", "red wali shirt lao"),
]

/// The same words said plainly in Hinglish, none of which may lose a word.
fileprivate let hinglishPlain: [TriggerCase] = [
    plain("nahi nahi", "nahi nahi mujhe nahi chahiye"),
    plain("nahi nahi", "wo nahi nahi bolta rehta hai"),
    plain("nahi nahi", "maine kaha nahi nahi aisa mat karo"),
    plain("nahi nahi", "teen baje nahi nahi ho payega"),
    plain("nahi nahi", "abhi nahi nahi baad mein baat karenge"),
    plain("nahi nahi", "do din nahi nahi chalega bhai"),
    plain("mera matlab", "mera matlab ye tha ki tum aa jao"),
    plain("mera matlab", "tum samjhe nahi mera matlab kya tha"),
    plain("mera matlab", "teen baje mera matlab chaar baje se pehle"),
    plain("mera matlab", "mera matlab, ye kaam kal tak ho jayega"),
    plain("no sorry", "usne no sorry bhi nahi bola"),
    plain("no", "maine usko no bola"),
    plain("no", "is mein no sugar hai"),
    plain("sorry", "sorry yaar main late ho gaya"),
    plain("sorry", "main late hoon sorry main abhi aata hoon"),
    plain("sorry", "usko sorry bolna padega"),
    plain("actually", "actually mujhe ye pasand hai"),
    plain("actually", "wo actually bahut accha hai"),
    plain("i mean", "i mean tum samajh rahe ho na"),
    plain("or rather", "tum chalo or rather nahi"),
    plain("correction", "correction ka kaam kal hoga"),
    plain("never mind", "never mind koi baat nahi"),
    plain("no wait", "no wait time hai yahan"),
    plain("wait sorry", "wait sorry bolne se kya hoga"),
    plain("scratch that", "ye scratch that wala sticker hai"),
    plain("strike that", "bowler strike that wicket"),
    plain("actually make it", "actually make it simple yaar"),
    plain("actually make that", "actually make that wala plan simple yaar"),
    plain("no make it", "no make it tomorrow wala idea chhodo"),
    plain("no sorry", "no sorry needed yaar"),
    plain("nahi nahi", "wo log nahi nahi karte rahe"),
    plain("mera matlab", "mera matlab samjho"),
    plain("galat bola", "usne mujhe galat bola"),
    plain("galat bola", "maine kuch galat bola kya"),
    plain("matlab", "iska matlab kya hai"),
    plain("matlab", "matlab tum kal nahi aaoge"),
    plain("nahi", "main kal nahi aa paunga"),
    plain("nahi", "wo paanch baje nahi aaya"),
    plain("nahi", "do log nahi, sab log aayenge"),
    plain("nahi", "mujhe do nahi, kuch nahi chahiye"),
    plain("nahi nahi", "bees rupaye nahi nahi chahiye"),
    plain("sorry sorry", "sorry sorry main bhool gaya"),
    plain("sorry sorry", "usko sorry sorry bolna padega"),
]

private let allCases = hinglishCorrections + hinglishPlain

/// Sentences the current evidence still reads wrongly, each held here until a fix makes it pass; see `Docs/cleanup.md`.
let owedTriggerCases: Set<String> = [
    "chai or rather coffee pi lete hain"
]

@Suite("Correction triggers, one table read by the same code for English and Hindi")
struct CorrectionTriggerTableTests {
    @Test("every correction in Hinglish takes back its first half", arguments: hinglishCorrections)
    func correctionsApply(item: TriggerCase) {
        let passes = applied(item.phrase, in: item.spoken) == .some(item.kept)
        #expect(passes != owedTriggerCases.contains(item.spoken), "update owedTriggerCases")
    }

    @Test("the same words said plainly in Hinglish lose nothing", arguments: hinglishPlain)
    func plainSpeechStays(item: TriggerCase) {
        let passes = applied(item.phrase, in: item.spoken) == .some(nil)
        #expect(passes != owedTriggerCases.contains(item.spoken), "update owedTriggerCases")
    }

    @Test("the Hinglish sets hold thirty sentences each")
    func setsAreFull() {
        #expect(hinglishCorrections.count >= 30)
        #expect(hinglishPlain.count >= 30)
    }

    @Test("every phrase in the table has a case that corrects and a case said plainly")
    func everyPhraseMeasuredBothWays() {
        for row in Restatement.table.rows {
            let phrase = row.words.joined(separator: " ")
            let cases = allCases.filter { $0.phrase == phrase }
            #expect(cases.contains { $0.kept != nil }, "\(row.id) has no correcting case")
            #expect(cases.contains { $0.kept == nil }, "\(row.id) has no plain case")
        }
    }

    @Test("every row names a language and a phrase in Latin letters")
    func rowsAreLatin() {
        for row in Restatement.table.rows {
            #expect(["en", "hi"].contains(row.language), "\(row.id)")
            #expect(row.words.allSatisfy { $0.unicodeScalars.allSatisfy { $0.isASCII } }, "\(row.id)")
        }
    }
}
