// Hinglish passages that switch language inside one sentence, one per direction and kind of word.

/// One passage per frame and kind of inserted word, with the switch spread evenly over start, middle and end.
enum CodeMixingPassages {
    /// Which language carries the sentence.
    enum Frame: String, CaseIterable {
        case english
        case hindi
    }

    /// What kind of word arrives from the other language.
    enum Insert: String, CaseIterable {
        case noun, verb, number, name, particle, tag

        var stressor: TranscriptionCase.Stressor {
            switch self {
            case .number: .digits
            case .name: .properNouns
            case .noun, .verb, .particle, .tag: .everyday
            }
        }
    }

    /// Where in the sentence the switch falls.
    enum Position: String, CaseIterable {
        case start, middle, end
    }

    /// The labels a report breaks this passage down by, one per axis of the matrix.
    static func stresses(_ frame: Frame, _ insert: Insert, _ position: Position) -> [String] {
        [
            insert.stressor.rawValue, CorpusStress.codeSwitching, "frame-\(frame.rawValue)",
            "insert-\(insert.rawValue)", "switch-\(position.rawValue)",
        ]
    }

    static func passage(
        _ frame: Frame, _ insert: Insert, _ position: Position, _ text: String, keep: [String] = []
    ) -> TranscriptionCase {
        .init(
            id: "mix-\(frame.rawValue)-\(insert.rawValue)-\(position.rawValue)", language: .hinglish,
            stressor: insert.stressor, romanised: text, mustKeep: keep,
            stresses: stresses(frame, insert, position))
    }

    static let all: [TranscriptionCase] = [
        passage(
            .english, .noun, .start,
            """
            Khana is on the table already, so come down before it goes cold, and bring the blue \
            folder with you because I need to sign the lease papers tonight.
            """, keep: ["Khana"]),
        passage(
            .english, .verb, .middle,
            """
            Please check karo the totals once more before you send the sheet to finance, because \
            last month two rows were wrong and nobody noticed until the audit.
            """, keep: ["karo"]),
        passage(
            .english, .number, .end,
            """
            We booked the hall for the whole evening and sent the invitations yesterday, but when \
            I counted the chairs this morning in the store room we only had barah.
            """),
        passage(
            .english, .name, .start,
            """
            Nandini called while you were out and said the train is running two hours late, so \
            nobody needs to leave for the station before seven tonight.
            """, keep: ["Nandini"]),
        passage(
            .english, .particle, .middle,
            """
            I told them twice already yaar, the meeting moved to Friday, but half the team still \
            turned up on Thursday and waited in the empty room.
            """, keep: ["yaar"]),
        passage(
            .english, .tag, .end,
            """
            You will send me the final slides by tomorrow evening so I can read them on the train \
            before the client review in the morning, hai na?
            """),
        passage(
            .hindi, .noun, .end,
            """
            Maine kal raat saara hisaab dobara dekha aur pata chala ki safar wala hissa abhi bhi \
            zyada hai, to thoda kam karna padega hamara budget.
            """, keep: ["budget"]),
        passage(
            .hindi, .verb, .start,
            """
            Cancel kar do wo kamra, kyunki mausi ab agle mahine aayengi aur tab tak kamra khaali \
            rakhne ka koi matlab nahi hai, paisa bhi bachega.
            """, keep: ["Cancel"]),
        passage(
            .hindi, .number, .middle,
            """
            Bazaar se lautte waqt twelve aam le aana, aur agar dukaan wale bhaiya ke paas chhutte \
            na hon to mujhe awaaz de dena, main yahin hun.
            """),
        passage(
            .hindi, .name, .end,
            """
            Kal subah jaldi nikalna hai, to saamaan raat ko hi baandh lena, aur hamein chhodne ke \
            liye jo aayega uska naam mujhe bas itna yaad hai, Daniel.
            """, keep: ["Daniel"]),
        passage(
            .hindi, .particle, .start,
            """
            Basically baat ye hai ki dono bhai ek hi din chutti le rahe hain, to dukaan us din kaun \
            kholega ye pehle tay karna padega.
            """, keep: ["Basically"]),
        passage(
            .hindi, .tag, .middle,
            """
            Tum kal aa rahe ho, right, to apne saath purani chaabi bhi le aana, warna darwaza phir \
            se mistri ko bula ke khulwana padega aur der hogi.
            """, keep: ["right"]),
    ]
}
