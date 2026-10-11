// Tests that the name class is stratified as committed and that its report scores and groups clips exactly.
import Foundation
import Testing

@testable import UttrflowEval

@Suite("Name class")
struct NameClassTests {
    private func item(
        _ name: String, _ origin: NameClassItem.Origin = .english, band: NameClassItem.Band = .common,
        kind: NameClassItem.Kind = .given
    ) -> NameClassItem {
        NameClassItem(id: "name-\(name.lowercased())", name: name, origin: origin, band: band, kind: kind)
    }

    private func row(_ item: NameClassItem, heard: String, inDictionary: Bool = false) -> NameClassRow {
        NameClassRow(
            item: item, voice: "Samantha", inDictionary: inDictionary,
            transcript: "\(item.kind.carrier.before) \(heard) \(item.kind.carrier.after).")
    }

    @Test("the bundled file holds 159 names")
    func bundledCount() throws {
        #expect(try NameClassCorpus.items().count == 159)
    }

    @Test("every origin has seven names in every band", arguments: NameClassItem.Origin.allCases)
    func everyOriginIsStratified(origin: NameClassItem.Origin) throws {
        let items = try NameClassCorpus.items().filter { $0.origin == origin && $0.kind != .wordAlike }
        for band in NameClassItem.Band.allCases {
            let inBand = items.filter { $0.band == band }
            #expect(inBand.filter { $0.kind == .given }.count == 3, "\(origin) \(band)")
            #expect(inBand.filter { $0.kind == .surname }.count == 2, "\(origin) \(band)")
            #expect(inBand.filter { $0.kind == .place }.count == 2, "\(origin) \(band)")
        }
    }

    @Test("four word-alike names sit in every band")
    func wordAlikeNames() throws {
        let items = try NameClassCorpus.items().filter { $0.kind == .wordAlike }
        #expect(
            NameClassItem.Band.allCases.map { band in items.filter { $0.band == band }.count } == [4, 4, 4])
    }

    @Test("every bundled name is Latin letters, apostrophes and spaces")
    func latinOnly() throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ' ")
        let refused = try NameClassCorpus.items().filter {
            !$0.name.unicodeScalars.allSatisfy(allowed.contains)
        }
        #expect(refused.isEmpty, "\(refused.map(\.name))")
    }

    @Test("a duplicate id or name refuses the whole file")
    func duplicatesRefused() {
        let id =
            #"[{"id":"a","name":"Priya","origin":"southAsian","band":"common","kind":"given"},"#
            + #"{"id":"a","name":"Rahul","origin":"southAsian","band":"common","kind":"given"}]"#
        let name =
            #"[{"id":"a","name":"Priya","origin":"southAsian","band":"common","kind":"given"},"#
            + #"{"id":"b","name":"Priya","origin":"southAsian","band":"common","kind":"place"}]"#
        #expect(throws: NameClassCorpus.Failure(reason: "duplicate id a")) {
            try NameClassCorpus.decode(Data(id.utf8))
        }
        #expect(throws: NameClassCorpus.Failure(reason: "duplicate name Priya")) {
            try NameClassCorpus.decode(Data(name.utf8))
        }
    }

    @Test("an unknown origin refuses the file")
    func unknownOrigin() {
        let text = #"[{"id":"a","name":"Priya","origin":"martian","band":"common","kind":"given"}]"#
        #expect(throws: NameClassCorpus.Failure.self) { try NameClassCorpus.decode(Data(text.utf8)) }
    }

    @Test("each kind reads in its own carrier")
    func sentences() {
        #expect(item("Siobhan").sentence == "I had a long call with Siobhan this morning")
        #expect(
            item("Sharma", kind: .surname).sentence == "the form was signed by Doctor Sharma this morning")
        #expect(item("Vadodara", kind: .place).sentence == "we are flying to Vadodara next week")
        #expect(item("Will", kind: .wordAlike).sentence == "I had a long call with Will this morning")
    }

    @Test("the carrier run is the words between the carrier's own")
    func carrierRun() {
        #expect(
            CarrierRun.words(in: "please write Vest again", before: "please write", after: "again")
                == ["vest"])
        #expect(CarrierRun.words(in: "please write again", before: "please write", after: "again") == nil)
        #expect(
            CarrierRun.words(
                in: "we are flying to Dun Laoghaire next week.", before: "we are flying to",
                after: "next week", normaliser: NameClassRow.spelling) == ["Dun", "Laoghaire"])
    }

    @Test("a lower-case name is spelled but not exact; a different word is neither")
    func scoring() {
        let will = item("Will", kind: .wordAlike)
        let exact = row(will, heard: "Will")
        let lower = row(will, heard: "will")
        let wrong = row(will, heard: "Phil")
        #expect([exact.isExact, exact.isSpelled] == [true, true])
        #expect([lower.isExact, lower.isSpelled] == [false, true])
        #expect([wrong.isExact, wrong.isSpelled] == [false, false])
        #expect(row(item("O'Sullivan", kind: .surname), heard: "O'Sullivan").isExact)
    }

    @Test("a transcript the carrier swallows is a miss marked too short")
    func tooShort() {
        let swallowed = NameClassRow(
            item: item("Liam"), voice: "Rishi", inDictionary: true, transcript: "I had a long call with")
        #expect(swallowed.heard == nil)
        #expect([swallowed.isExact, swallowed.isSpelled] == [false, false])
        #expect(
            swallowed.line
                == "Rishi\tdictionary\tenglish\tcommon\tgiven\tLiam\t<too short>\tI had a long call with")
    }

    @Test("the origin and band table counts each group and each band over every origin")
    func originBandTable() {
        let priya = item("Priya", .southAsian)
        let wojciech = item("Wojciech", .slavic, band: .rare)
        let report = NameClassReport(rows: [
            row(priya, heard: "Priya"), row(priya, heard: "Pria", inDictionary: true),
            row(wojciech, heard: "voy check"), row(wojciech, heard: "Wojciech", inDictionary: true),
        ])
        #expect(
            report.originBandTable == """
                | Origin | Band | Plain clips | Dictionary clips | Exact, plain | Exact, dictionary \
                | Spelled, plain | Spelled, dictionary |
                |---|---|---|---|---|---|---|---|
                | southAsian | common | 1 | 1 | 100.0% | 0.0% | 100.0% | 0.0% |
                | slavic | rare | 1 | 1 | 0.0% | 100.0% | 0.0% | 100.0% |
                | all | common | 1 | 1 | 100.0% | 0.0% | 100.0% | 0.0% |
                | all | rare | 1 | 1 | 0.0% | 100.0% | 0.0% | 100.0% |
                """)
    }

    @Test("the kind table shows a missing condition as n/a")
    func kindTable() {
        let report = NameClassReport(rows: [row(item("Will", kind: .wordAlike), heard: "will")])
        #expect(
            report.kindTable == """
                | Kind | Plain clips | Dictionary clips | Exact, plain | Exact, dictionary \
                | Spelled, plain | Spelled, dictionary |
                |---|---|---|---|---|---|---|
                | wordAlike | 1 | 0 | 0.0% | n/a | 100.0% | n/a |
                """)
    }

    @Test("the weakest band is the least exact without the dictionary, a tie going to the rarer")
    func weakestBand() {
        let common = item("Sarah")
        let uncommon = item("Imogen", band: .uncommon)
        let rare = item("Crispin", band: .rare)
        #expect(NameClassReport(rows: []).weakestBand == nil)
        #expect(
            NameClassReport(rows: [
                row(common, heard: "Sara"), row(uncommon, heard: "Imogen"),
                row(rare, heard: "Crispin"), row(rare, heard: "crisp in", inDictionary: true),
            ]).weakestBand == .common)
        #expect(
            NameClassReport(rows: [row(common, heard: "Sara"), row(uncommon, heard: "Imagine")])
                .weakestBand == .uncommon)
    }

    @Test("confusions list each heard form once per name, counted by condition")
    func confusions() {
        let niamh = item("Niamh", .irishScottish, band: .uncommon)
        let report = NameClassReport(rows: [
            row(niamh, heard: "Neve"), row(niamh, heard: "Neve", inDictionary: true),
            row(niamh, heard: "Neve"), row(niamh, heard: "Niamh", inDictionary: true),
            row(item("Sarah"), heard: "Sara"),
        ])
        #expect(
            report.confusions == """
                | Band | Origin | Meant | Heard | Plain | Dictionary |
                |---|---|---|---|---|---|
                | common | english | Sarah | Sara | 1 | 0 |
                | uncommon | irishScottish | Niamh | Neve | 2 | 1 |
                """)
    }
}
