import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary

/// How often an English loanword in Devanagari comes out spelt by sound, and how many a safe match could restore. See `Docs/latin-output.md`.
@Suite("Loanword restoration probe")
struct LoanwordRestorationProbeTests {
    /// What the romaniser and a guard-style match do with one Devanagari word.
    enum Outcome: String, CaseIterable {
        case spelt, restorable, soundOnly, unreachable
    }

    /// The English word the guard's acceptance test would put back for a romanised word, only when exactly one ordinary word qualifies.
    static func restoration(of romanised: String) -> String? {
        let matches = GeneralVocabulary.wordsSounding(like: romanised).filter {
            $0 != romanised && MeaningPreservationGuard.isRespelling(romanised, as: $0)
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// Sorts one loanword into what happens to it today and what the matcher could do.
    static func outcome(_ devanagari: String, english: String) -> Outcome {
        let romanised = Romaniser.romanised(devanagari).lowercased()
        if romanised == english { return .spelt }
        if restoration(of: romanised) == english { return .restorable }
        return MeaningPreservationGuard.isRespelling(romanised, as: english) ? .soundOnly : .unreachable
    }

    /// Invented loanwords, written the way a recogniser writes them in Devanagari, with the spelling a Hinglish typist uses.
    static let loanwords: [(String, String)] = [
        ("मैनेजर", "manager"), ("टिकट", "ticket"), ("कैंसल", "cancel"), ("बजट", "budget"),
        ("क्लाइंट", "client"), ("अपडेट", "update"), ("ड्राफ्ट", "draft"), ("डॉक्यूमेंट", "document"),
        ("फ़ोल्डर", "folder"), ("लिंक", "link"), ("पिक्चर", "picture"), ("शेड्यूल", "schedule"),
        ("कैलेंडर", "calendar"), ("रिमाइंडर", "reminder"), ("टास्क", "task"), ("लिस्ट", "list"),
        ("प्लान", "plan"), ("रिव्यू", "review"), ("एजेंडा", "agenda"), ("समरी", "summary"),
        ("वीकेंड", "weekend"), ("मंथली", "monthly"), ("वीकली", "weekly"), ("डेली", "daily"),
        ("सर्विस", "service"), ("कंपनी", "company"), ("सिस्टम", "system"), ("प्रोग्राम", "program"),
        ("टीम", "team"), ("मेंबर", "member"), ("पार्टी", "party"), ("रिज़ल्ट", "result"),
        ("चेंज", "change"), ("रीज़न", "reason"), ("रिसर्च", "research"), ("टीचर", "teacher"),
        ("एजुकेशन", "education"), ("रिपोर्ट", "report"), ("बिज़नेस", "business"), ("इश्यू", "issue"),
        ("गेम", "game"), ("लाइन", "line"), ("आइडिया", "idea"), ("हिस्ट्री", "history"),
        ("स्टोरी", "story"), ("प्रेसिडेंट", "president"), ("कम्युनिटी", "community"), ("स्टूडेंट", "student"),
        ("ग्रुप", "group"), ("क्वेश्चन", "question"), ("नंबर", "number"), ("मंडे", "monday"),
        ("फ्राइडे", "friday"), ("डिनर", "dinner"), ("लंच", "lunch"), ("ब्रेकफास्ट", "breakfast"),
        ("ट्रेन", "train"), ("बस", "bus"), ("स्टेशन", "station"), ("एयरपोर्ट", "airport"),
        ("होटल", "hotel"), ("हॉस्पिटल", "hospital"), ("मार्केट", "market"), ("शॉपिंग", "shopping"),
        ("ऑर्डर", "order"), ("डिलीवरी", "delivery"), ("पेमेंट", "payment"), ("कार्ड", "card"),
        ("कैश", "cash"), ("बिल", "bill"), ("सैलरी", "salary"), ("इंटरव्यू", "interview"),
        ("ऑफ़र", "offer"), ("जॉब", "job"), ("बॉस", "boss"), ("प्रेजेंटेशन", "presentation"),
        ("स्लाइड", "slide"), ("चार्ट", "chart"), ("डेटा", "data"), ("सर्वर", "server"),
        ("ऐप", "app"), ("सॉफ्टवेयर", "software"), ("बग", "bug"), ("टेस्ट", "test"),
        ("रिलीज़", "release"), ("फ़ीचर", "feature"), ("डिज़ाइन", "design"), ("कोड", "code"),
        ("स्क्रीन", "screen"), ("बटन", "button"), ("विंडो", "window"), ("कीबोर्ड", "keyboard"),
        ("प्रिंटर", "printer"), ("चार्जर", "charger"), ("बैटरी", "battery"), ("नेटवर्क", "network"),
        ("वाईफाई", "wifi"), ("ब्राउज़र", "browser"), ("वेबसाइट", "website"), ("अकाउंट", "account"),
    ]

    /// Ordinary Hindi words a restoration must never touch, written as a recogniser writes them.
    static let hindiWords: [String] = [
        "कल", "दिल", "काम", "नाम", "घर", "दिन", "रात", "बात", "पानी", "खाना", "चाय", "दूध", "माँ", "पापा",
        "बेटा", "बेटी", "दोस्त", "लड़का", "लड़की", "आदमी", "औरत", "बच्चा", "सुबह", "शाम", "रास्ता", "गाड़ी",
        "सड़क", "शहर", "गाँव", "देश", "पैसा", "किताब", "कमरा", "दरवाज़ा", "खिड़की", "मेज़", "कुर्सी", "बाज़ार",
        "दुकान", "सब्ज़ी", "फल", "आम", "केला", "रोटी", "दाल", "चावल", "नमक", "चीनी", "तेल", "मसाला",
        "मीठा", "कड़वा", "गरम", "ठंडा", "बड़ा", "छोटा", "नया", "पुराना", "अच्छा", "बुरा", "सही", "गलत",
        "जल्दी", "देर", "आना", "जाना", "करना", "देखना", "सुनना", "बोलना", "लिखना", "पढ़ना", "सोना",
        "उठना", "बैठना", "चलना", "दौड़ना", "खेलना", "हँसना", "रोना", "मिलना", "भेजना", "लेना", "देना",
        "सोच", "समझ", "प्यार", "गुस्सा", "डर", "खुशी", "दुख", "मन", "जान", "बाल", "हाथ", "पैर", "आँख",
        "कान", "मुँह", "सिर", "पेट", "दाँत", "बहन", "भाई", "चाचा", "मामा", "नानी", "दादी", "पति", "पत्नी",
        "शादी", "त्योहार", "पूजा", "मंदिर", "भगवान", "सपना", "सच", "झूठ", "हवा", "धूप", "बारिश", "पेड़",
    ]

    /// The probe table recorded in `Docs/latin-output.md`; a change to the romaniser or the matcher that moves it fails here.
    @Test func probeTable() {
        var counts: [Outcome: [String]] = [:]
        for (devanagari, english) in Self.loanwords {
            let romanised = Romaniser.romanised(devanagari).lowercased()
            counts[Self.outcome(devanagari, english: english), default: []].append("\(english)=\(romanised)")
        }
        for outcome in Outcome.allCases {
            let words = counts[outcome] ?? []
            print("PROBE \(outcome.rawValue) \(words.count): \(words.joined(separator: " "))")
        }
        let wrongful = Self.hindiWords.compactMap { devanagari -> String? in
            let romanised = Romaniser.romanised(devanagari).lowercased()
            return Self.restoration(of: romanised).map { "\(romanised)->\($0)" }
        }
        print(
            "PROBE hindi \(Self.hindiWords.count), restored \(wrongful.count): \(wrongful.joined(separator: " "))"
        )
        #expect(counts.mapValues(\.count) == [.spelt: 9, .restorable: 13, .soundOnly: 63, .unreachable: 15])
        #expect(wrongful.count == 8)
    }
}
