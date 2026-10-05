// Invented English-frame sentences carrying Hindi words, one block per code-mixing cell. See Docs/code-mixing-matrix.md.
import UttrflowCore

extension EvaluationCorpus {
    static let codeMixing: [EvaluationCase] =
        englishNoun + englishVerb + englishNumber + englishName + englishParticle + englishTag

    /// A code-mixing case: the Hindi words stay in Latin letters, untranslated, and nothing is dropped.
    private static func mix(
        _ id: String, _ kind: CodeMixCell.Kind, _ position: CodeMixCell.Position,
        _ spoken: String, _ expected: String, keep: [String], notAdd: [String] = []
    ) -> EvaluationCase {
        .init(
            id: "mix-en-\(kind.rawValue)-\(position.rawValue)-\(id)", category: .multilingual,
            spoken: spoken, expected: expected, mustKeep: keep, mustNotAdd: notAdd,
            codeMix: CodeMixCell(.english, kind, position), addedFor: 3820)
    }

    static let englishNoun: [EvaluationCase] = [
        mix(
            "chai", .noun, .start, "chai is ready come to the kitchen", "Chai is ready, come to the kitchen.",
            keep: ["Chai", "kitchen"], notAdd: ["tea"]),
        mix(
            "khana", .noun, .start, "khana will be late tonight", "Khana will be late tonight.",
            keep: ["Khana", "late"], notAdd: ["food"]),
        mix(
            "dukaan", .noun, .start, "dukaan closes at nine today", "Dukaan closes at nine today.",
            keep: ["Dukaan", "closes"], notAdd: ["shop"]),
        mix(
            "paisa", .noun, .start, "paisa is not the problem here", "Paisa is not the problem here.",
            keep: ["Paisa", "problem"], notAdd: ["money"]),
        mix(
            "ghar", .noun, .middle, "I will reach ghar by seven", "I will reach ghar by seven.",
            keep: ["ghar", "reach"], notAdd: ["home"]),
        mix(
            "kaam", .noun, .middle, "there is too much kaam this week", "There is too much kaam this week.",
            keep: ["kaam", "week"], notAdd: ["work"]),
        mix(
            "sabzi", .noun, .middle, "please buy some sabzi on the way back",
            "Please buy some sabzi on the way back.",
            keep: ["sabzi", "way"], notAdd: ["vegetables"]),
        mix(
            "chabi", .noun, .middle, "the chabi is on the table", "The chabi is on the table.",
            keep: ["chabi", "table"], notAdd: ["key"]),
        mix(
            "baarish", .noun, .end, "we cancelled the match because of baarish",
            "We cancelled the match because of baarish.",
            keep: ["baarish", "cancelled"], notAdd: ["rain"]),
        mix(
            "mithai", .noun, .end, "do not forget to bring the mithai", "Do not forget to bring the mithai.",
            keep: ["mithai", "forget"], notAdd: ["sweets"]),
        mix(
            "gaadi", .noun, .end, "I parked outside in the old gaadi", "I parked outside in the old gaadi.",
            keep: ["gaadi", "parked"], notAdd: ["car"]),
        mix(
            "dawai", .noun, .end, "remind her to take the dawai", "Remind her to take the dawai.",
            keep: ["dawai", "Remind"], notAdd: ["medicine"]),
    ]

    static let englishVerb: [EvaluationCase] = [
        mix(
            "chalo", .verb, .start, "chalo let us start the call", "Chalo, let us start the call.",
            keep: ["Chalo", "call"], notAdd: ["come on"]),
        mix(
            "ruko", .verb, .start, "ruko I am still reading it", "Ruko, I am still reading it.",
            keep: ["Ruko", "reading"], notAdd: ["wait"]),
        mix(
            "dekho", .verb, .start, "dekho the numbers do not match", "Dekho, the numbers do not match.",
            keep: ["Dekho", "numbers"], notAdd: ["look"]),
        mix(
            "suno", .verb, .start, "suno the meeting moved to Friday", "Suno, the meeting moved to Friday.",
            keep: ["Suno", "Friday"], notAdd: ["listen"]),
        mix(
            "bhej-do", .verb, .middle, "just bhej do the file when it is ready",
            "Just bhej do the file when it is ready.",
            keep: ["bhej", "file"], notAdd: ["send"]),
        mix(
            "dekh-lo", .verb, .middle, "can you dekh lo the draft once", "Can you dekh lo the draft once?",
            keep: ["dekh", "draft"], notAdd: ["check"]),
        mix(
            "kar-dena", .verb, .middle, "please kar dena the booking tonight",
            "Please kar dena the booking tonight.",
            keep: ["kar", "booking"], notAdd: ["do it"]),
        mix(
            "samjha-do", .verb, .middle, "you should samjha do the plan to them",
            "You should samjha do the plan to them.",
            keep: ["samjha", "plan"], notAdd: ["explain"]),
        mix(
            "aa-jao", .verb, .end, "the food is here so aa jao", "The food is here, so aa jao.",
            keep: ["aa", "jao"], notAdd: ["come"]),
        mix(
            "baith-jao", .verb, .end, "there are free seats so baith jao",
            "There are free seats, so baith jao.",
            keep: ["baith", "seats"], notAdd: ["sit"]),
        mix(
            "so-jao", .verb, .end, "it is already midnight so so jao", "It is already midnight, so so jao.",
            keep: ["jao", "midnight"], notAdd: ["sleep"]),
        mix(
            "nikal-jao", .verb, .end, "the cab is outside nikal jao", "The cab is outside, nikal jao.",
            keep: ["nikal", "cab"], notAdd: ["leave"]),
    ]

    static let englishNumber: [EvaluationCase] = [
        mix(
            "paanch", .number, .start, "paanch people are coming tonight",
            "Paanch people are coming tonight.",
            keep: ["Paanch", "people"], notAdd: ["five", "5"]),
        mix(
            "das", .number, .start, "das minutes and I will be there", "Das minutes and I will be there.",
            keep: ["Das", "minutes"], notAdd: ["ten", "10"]),
        mix(
            "teen", .number, .start, "teen copies are enough for the room",
            "Teen copies are enough for the room.",
            keep: ["Teen", "copies"], notAdd: ["three", "3"]),
        mix(
            "char", .number, .start, "char tickets are left for Sunday", "Char tickets are left for Sunday.",
            keep: ["Char", "tickets"], notAdd: ["four", "4"]),
        mix(
            "do", .number, .middle, "we need do more chairs in here", "We need do more chairs in here.",
            keep: ["do", "chairs"], notAdd: ["two", "2"]),
        mix(
            "saat", .number, .middle, "the shop opens at saat in the morning",
            "The shop opens at saat in the morning.",
            keep: ["saat", "morning"], notAdd: ["seven", "7"]),
        mix(
            "aath", .number, .middle, "book a table for aath people", "Book a table for aath people.",
            keep: ["aath", "table"], notAdd: ["eight", "8"]),
        mix(
            "sau", .number, .middle, "it costs about sau rupees each", "It costs about sau rupees each.",
            keep: ["sau", "rupees"], notAdd: ["hundred", "100"]),
        mix(
            "chhe", .number, .end, "the train leaves at chhe", "The train leaves at chhe.",
            keep: ["chhe", "train"], notAdd: ["six", "6"]),
        mix(
            "nau", .number, .end, "the class starts at nau", "The class starts at nau.",
            keep: ["nau", "class"], notAdd: ["nine", "9"]),
        mix(
            "ek", .number, .end, "I only need ek", "I only need ek.",
            keep: ["ek", "need"], notAdd: ["one", "1"]),
        mix(
            "bees", .number, .end, "the guest list is at bees", "The guest list is at bees.",
            keep: ["bees", "guest"], notAdd: ["twenty", "20"]),
    ]

    static let englishName: [EvaluationCase] = [
        mix(
            "didi", .name, .start, "didi said the parcel came", "Didi said the parcel came.",
            keep: ["Didi", "parcel"], notAdd: ["sister"]),
        mix(
            "bhaiya", .name, .start, "bhaiya will drop us at the station",
            "Bhaiya will drop us at the station.",
            keep: ["Bhaiya", "station"], notAdd: ["brother"]),
        mix(
            "nani", .name, .start, "nani wants to visit on Sunday", "Nani wants to visit on Sunday.",
            keep: ["Nani", "Sunday"], notAdd: ["grandmother"]),
        mix(
            "chacha", .name, .start, "chacha fixed the gate already", "Chacha fixed the gate already.",
            keep: ["Chacha", "gate"], notAdd: ["uncle"]),
        mix(
            "mausi", .name, .middle, "tell mausi the plan changed", "Tell Mausi the plan changed.",
            keep: ["Mausi", "plan"], notAdd: ["aunt"]),
        mix(
            "dadi", .name, .middle, "I called dadi this morning", "I called Dadi this morning.",
            keep: ["Dadi", "morning"], notAdd: ["grandmother"]),
        mix(
            "bhabhi", .name, .middle, "ask bhabhi about the guest list", "Ask Bhabhi about the guest list.",
            keep: ["Bhabhi", "guest"], notAdd: ["sister-in-law"]),
        mix(
            "mama", .name, .middle, "we are meeting mama at the airport",
            "We are meeting Mama at the airport.",
            keep: ["Mama", "airport"], notAdd: ["uncle"]),
        mix(
            "didi-end", .name, .end, "the cake was made by didi", "The cake was made by Didi.",
            keep: ["Didi", "cake"], notAdd: ["sister"]),
        mix(
            "chachi", .name, .end, "the spare keys are with chachi", "The spare keys are with Chachi.",
            keep: ["Chachi", "keys"], notAdd: ["aunt"]),
        mix(
            "nana", .name, .end, "save a seat for nana", "Save a seat for Nana.",
            keep: ["Nana", "seat"], notAdd: ["grandfather"]),
        mix(
            "bhaiya-end", .name, .end, "the bill was paid by bhaiya", "The bill was paid by Bhaiya.",
            keep: ["Bhaiya", "bill"], notAdd: ["brother"]),
    ]

    static let englishParticle: [EvaluationCase] = [
        mix(
            "arre", .particle, .start, "arre the bus already left", "Arre, the bus already left.",
            keep: ["Arre", "bus"]),
        mix(
            "acha", .particle, .start, "acha so the meeting is at four", "Acha, so the meeting is at four.",
            keep: ["Acha", "meeting"], notAdd: ["okay"]),
        mix(
            "haan", .particle, .start, "haan that works for me", "Haan, that works for me.",
            keep: ["Haan", "works"], notAdd: ["yes"]),
        mix(
            "bas", .particle, .start, "bas that is all for today", "Bas, that is all for today.",
            keep: ["Bas", "today"], notAdd: ["enough"]),
        mix(
            "toh", .particle, .middle, "the shop was shut toh we came back",
            "The shop was shut, toh we came back.",
            keep: ["toh", "shut"], notAdd: ["so we"]),
        mix(
            "bhi", .particle, .middle, "I bhi want to come along", "I bhi want to come along.",
            keep: ["bhi", "along"], notAdd: ["also"]),
        mix(
            "hi", .particle, .middle, "she hi finished the slides", "She hi finished the slides.",
            keep: ["hi", "slides"], notAdd: ["only"]),
        mix(
            "matlab", .particle, .middle, "the price is matlab a bit high", "The price is matlab a bit high.",
            keep: ["matlab", "price"], notAdd: ["meaning"]),
        mix(
            "yaar", .particle, .end, "this traffic is crazy yaar", "This traffic is crazy, yaar.",
            keep: ["yaar", "traffic"], notAdd: ["friend"]),
        mix(
            "bas-end", .particle, .end, "one more slide and bas", "One more slide and bas.",
            keep: ["bas", "slide"], notAdd: ["enough"]),
        mix(
            "re", .particle, .end, "hurry up re", "Hurry up re.",
            keep: ["re", "Hurry"]),
        mix(
            "ji", .particle, .end, "thank you so much ji", "Thank you so much ji.",
            keep: ["ji", "Thank"]),
    ]

    static let englishTag: [EvaluationCase] = [
        mix(
            "theek-hai", .questionTag, .start, "theek hai we leave at five", "Theek hai, we leave at five.",
            keep: ["Theek", "leave"], notAdd: ["okay"]),
        mix(
            "hai-na", .questionTag, .start, "hai na the store is open late",
            "Hai na, the store is open late.",
            keep: ["Hai", "store"], notAdd: ["right"]),
        mix(
            "samjhe", .questionTag, .start, "samjhe the form goes in by Monday",
            "Samjhe, the form goes in by Monday.",
            keep: ["Samjhe", "Monday"], notAdd: ["understood"]),
        mix(
            "kya", .questionTag, .start, "kya you finished the report", "Kya you finished the report?",
            keep: ["Kya", "report"], notAdd: ["what"]),
        mix(
            "na-mid", .questionTag, .middle, "you will come na and bring the charger",
            "You will come na and bring the charger.",
            keep: ["na", "charger"]),
        mix(
            "hai-na-mid", .questionTag, .middle, "it is Monday hai na so the office is open",
            "It is Monday hai na, so the office is open.",
            keep: ["hai", "office"], notAdd: ["right"]),
        mix(
            "theek-hai-mid", .questionTag, .middle, "we split the bill theek hai and settle later",
            "We split the bill theek hai and settle later.",
            keep: ["theek", "settle"], notAdd: ["okay"]),
        mix(
            "samjhe-mid", .questionTag, .middle, "the door code changed samjhe so update the note",
            "The door code changed samjhe, so update the note.",
            keep: ["samjhe", "code"], notAdd: ["understood"]),
        mix(
            "theek-hai-end", .questionTag, .end, "send me the report kal tak theek hai",
            "Send me the report kal tak, theek hai?",
            keep: ["kal", "theek"], notAdd: ["tomorrow", "okay"]),
        mix(
            "hai-na-end", .questionTag, .end, "you are coming to the wedding hai na",
            "You are coming to the wedding, hai na?",
            keep: ["hai", "wedding"], notAdd: ["right"]),
        mix(
            "na-end", .questionTag, .end, "you saw my message na", "You saw my message, na?",
            keep: ["na", "message"]),
        mix(
            "samjhe-end", .questionTag, .end, "the deadline is firm samjhe", "The deadline is firm, samjhe?",
            keep: ["samjhe", "deadline"], notAdd: ["understood"]),
    ]
}
