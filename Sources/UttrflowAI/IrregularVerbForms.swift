/// The common irregular verb form-sets, so the guard can see "went" surviving as "gone".
enum IrregularVerbForms {
    /// Each set holds every form of one verb; two words are forms of each other when they share a set.
    static let sets: [[String]] = [
        ["go", "went", "gone"],
        ["do", "does", "did", "done"],
        ["be", "is", "are", "was", "were", "been", "am"],
        ["have", "has", "had"],
        ["take", "took", "taken"],
        ["come", "came"],
        ["see", "saw", "seen"],
        ["get", "got", "gotten"],
        ["write", "wrote", "written"],
        ["run", "ran"],
        ["know", "knew", "known"],
        ["think", "thought"],
        ["buy", "bought"],
        ["bring", "brought"],
        ["catch", "caught"],
        ["teach", "taught"],
        ["feel", "felt"],
        ["keep", "kept"],
        ["leave", "left"],
        ["lose", "lost"],
        ["make", "made"],
        ["say", "said"],
        ["sell", "sold"],
        ["send", "sent"],
        ["sit", "sat"],
        ["speak", "spoke", "spoken"],
        ["stand", "stood"],
        ["tell", "told"],
        ["eat", "ate", "eaten"],
        ["fall", "fell", "fallen"],
        ["give", "gave", "given"],
        ["drive", "drove", "driven"],
        ["break", "broke", "broken"],
        ["choose", "chose", "chosen"],
        ["forget", "forgot", "forgotten"],
    ]

    /// Which set a lowercased form belongs to, or `nil` for a word no set holds.
    static let setIndex: [String: Int] = Dictionary(
        uniqueKeysWithValues: sets.enumerated().flatMap { index, forms in
            forms.map { ($0, index) }
        })
}
