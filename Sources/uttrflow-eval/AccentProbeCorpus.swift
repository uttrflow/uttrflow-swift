// Invented carrier sentences around minimal-pair words, one list per accent class.

/// One word to be heard, the class it tests, and the carrier that anchors it in the transcript.
struct AccentProbeItem {
    let accentClass: String
    let word: String
    let carrier: AccentCarrier
    var sentence: String { "\(carrier.before) \(word) \(carrier.after)" }
}

/// Fixed words either side of the target, so what the recogniser made of it is the run between them.
struct AccentCarrier {
    let before: String
    let after: String
}

enum AccentProbeCorpus {
    static let englishCarriers = [
        AccentCarrier(before: "please write", after: "again"),
        AccentCarrier(before: "I said", after: "twice"),
        AccentCarrier(before: "the next word is", after: "okay"),
    ]
    static let hindiCarrier = AccentCarrier(before: "mujhe", after: "wala setup chahiye")

    /// Each class lists 30 words: both halves of 15 minimal pairs, or 30 words of the shape the class drops.
    static let classes: [(String, [String])] = [
        (
            "v/w",
            words(
                """
                vest west vine wine veil whale vet wet vent went vow wow verse worse vile while viper wiper \
                vary wary veal wheel vain wane vise wise vend wend vex wax
                """)
        ),
        (
            "th as t/d/s/f",
            words(
                """
                tree three den then tin thin sink think fought thought tank thank dare there day they sum \
                thumb free three fin thin taught thought dough though tie thigh true through
                """)
        ),
        (
            "l/r",
            words(
                """
                lock rock light right lead read late rate long wrong law raw lane rain lice rice load road \
                lamp ramp glass grass fly fry play pray collect correct alive arrive
                """)
        ),
        (
            "s/z",
            words(
                """
                sip zip sink zinc seal zeal sue zoo bus buzz peace peas race raise loose lose place plays \
                price prize rice rise ice eyes face phase sown zone cease seize
                """)
        ),
        (
            "sh/s",
            words(
                """
                ship sip sheet seat shell sell shine sign shoe sue sheep seep shore sore shock sock shame same \
                shave save sheer seer short sort mesh mess crash crass shift sift
                """)
        ),
        (
            "h-dropping",
            words(
                """
                hair air heat eat hold old hand and harm arm hit it heal eel hear ear hall all hate eight \
                hedge edge high eye hill ill heart art hitch itch
                """)
        ),
        (
            "prothetic vowel",
            words(
                """
                school station stop speak street stack string sprint script stream spoon sport star stage \
                smart snake spring special study style slow skill stamp steel story space square stable stick \
                store
                """)
        ),
        (
            "vowel length",
            words(
                """
                bit beat ship sheep full fool live leave fill feel hit heat sit seat pull pool slip sleep chip \
                cheap mill meal rich reach still steal fit feet pick peak
                """)
        ),
        (
            "final consonant",
            words(
                """
                test desk fast hand last past mist wind bend cold field build ask list cost west lift belt \
                sold mind gift kept act fact soft paint tend tempt worst burnt
                """)
        ),
        (
            "retroflex t/d",
            words(
                """
                data water better today doctor ladder matter daughter tender tidy dirty twenty title metal \
                medal total model under bottle toad tight dart tart dent tent dote tote deck tick dock
                """)
        ),
    ]

    /// Invented technical terms, each said in an English carrier and in a Hindi one.
    static let technicalTerms = words(
        """
        Kubernetes Django PostgreSQL Redis nginx GraphQL TypeScript Webpack Terraform Ansible Jenkins \
        Grafana Kafka RabbitMQ Elasticsearch MongoDB SQLite OAuth JSON YAML Docker Heroku Vercel Netlify \
        Flutter Kotlin Swift Xcode Gradle Maven PyTorch TensorFlow NumPy pandas Jupyter FastAPI Flask \
        Laravel Symfony Prisma Supabase Firebase Tailwind Svelte Nuxt Vite ESLint Prettier Homebrew Zsh
        """
    )

    /// Every item: 300 accent sentences, then 50 terms in English and 50 inside Hindi.
    static var items: [AccentProbeItem] {
        var items: [AccentProbeItem] = []
        for (name, list) in classes {
            for (index, word) in list.enumerated() {
                items.append(
                    AccentProbeItem(
                        accentClass: name, word: word, carrier: englishCarriers[index % englishCarriers.count]
                    ))
            }
        }
        for (index, term) in technicalTerms.enumerated() {
            items.append(
                AccentProbeItem(
                    accentClass: "term in English", word: term,
                    carrier: englishCarriers[index % englishCarriers.count]))
            items.append(AccentProbeItem(accentClass: "term in Hindi", word: term, carrier: hindiCarrier))
        }
        return items
    }

    private static func words(_ list: String) -> [String] { list.split(separator: " ").map(String.init) }
}
