import Testing

@testable import UttrflowPredict

/// The git subcommands a machine with a repository in front of it would list.
private let subcommands: Set<String> = ["commit", "checkout", "status", "stash", "push"]

/// The word a candidate ends on, which is what the gates judge.
private func word(_ line: String) -> CompletionToken? { CompletionToken(line) }

@Suite("Correctness above habit")
struct VerificationTests {
    @Test("A word the machine vouches for is attested, however unlikely the model finds it.")
    func attestationOutranksTheModel() {
        #expect(Verification.verdict(word: "cm", known: ["cm", "commit"], modelObjects: true) == .attested)
    }

    @Test("A word one cheap slip from a name the machine knows is corrected to that name.")
    func correctsOneSlip() {
        #expect(
            Verification.verdict(word: "comit", known: subcommands, modelObjects: false)
                == .corrected("commit"))
        #expect(
            Verification.verdict(word: "stauts", known: subcommands, modelObjects: false)
                == .corrected("status"))
    }

    @Test("A machine that has said nothing has not denied anything, so the candidate stands.")
    func silenceIsNotDenial() {
        #expect(Verification.verdict(word: "comit", known: [], modelObjects: false) == .plausible)
    }

    @Test("A word the machine cannot place and the model dislikes is not offered at all.")
    func rejectsWhatNothingSupports() {
        #expect(Verification.verdict(word: "zqxjw", known: subcommands, modelObjects: true) == .rejected)
    }

    @Test("A word the machine cannot place still stands while nothing objects to it.")
    func keepsWhatNothingObjectsTo() {
        #expect(Verification.verdict(word: "zqxjw", known: subcommands, modelObjects: false) == .plausible)
    }

    @Test("Nothing under three characters is corrected, because a short word matches everything.")
    func shortWordsAreNeverCorrected() {
        #expect(Verification.nearestNeighbour(of: "cm", among: subcommands) == nil)
        #expect(Verification.nearestNeighbour(of: "", among: subcommands) == nil)
    }

    @Test("A slip in the first character is not corrected, because people rarely make one.")
    func firstCharacterIsLeftAlone() {
        #expect(Verification.nearestNeighbour(of: "xommit", among: subcommands) == nil)
    }

    @Test("A key nowhere near the intended one is too far to be a slip.")
    func distantSubstitutionIsNotASlip() {
        #expect(Verification.nearestNeighbour(of: "commiz", among: subcommands) == nil)
    }

    @Test("A neighbour beside the intended key is close enough to be a slip.")
    func adjacentSubstitutionIsASlip() {
        #expect(Verification.nearestNeighbour(of: "commir", among: subcommands) == "commit")
    }

    @Test("Two neighbours equally near are settled in one order rather than by chance.")
    func tiesAreSettledTheSameWayEveryTime() {
        #expect(Verification.nearestNeighbour(of: "abc", among: ["axbc", "abyc"]) == "abyc")
    }

    @Test("A word already in the machine's list is never corrected to something else.")
    func aKnownWordIsNotCorrected() {
        #expect(Verification.verdict(word: "stash", known: subcommands, modelObjects: false) == .attested)
    }

    @Test("The model objects only when it has scored the candidate below the floor.")
    func objectionNeedsAScore() {
        #expect(Verification.objects(to: .scored(Verification.plausibilityFloor - 1)))
        #expect(!Verification.objects(to: .scored(Verification.plausibilityFloor)))
        #expect(!Verification.objects(to: .silent))
        #expect(!Verification.objects(to: .overBudget))
    }

    @Test("The first word of a line is vouched for by programs and shell aliases.")
    func firstWordIsAProgram() throws {
        let token = try #require(word("gi"))
        #expect(Verification.attestingKinds(for: token) == [.executable, .alias])
    }

    @Test("The word after git is vouched for by git's own subcommands and the user's git aliases.")
    func gitSubcommandsVouchForTheSecondWord() throws {
        let token = try #require(word("git comit"))
        #expect(Verification.attestingKinds(for: token) == [.gitSubcommand, .gitAlias])
    }

    @Test("The word after any other command is vouched for by branches and filenames.")
    func argumentsAreBranchesAndFiles() throws {
        #expect(Verification.attestingKinds(for: try #require(word("make verif"))) == [.branch, .file])
        #expect(
            Verification.attestingKinds(for: try #require(word("git checkout mai")))
                == [.branch, .file])
    }

    @Test("A verdict says whether the machine vouched for it and whether anything may be drawn.")
    func verdictsReadTheirOwnMeaning() {
        #expect(Verdict.attested.isAttested)
        #expect(!Verdict.plausible.isAttested)
        #expect(Verdict.plausible.allowsOffering)
        #expect(Verdict.corrected("git commit").allowsOffering)
        #expect(!Verdict.rejected.allowsOffering)
    }
}

@Suite("The names git binds")
struct GitAliasesTests {
    @Test("Every alias git configuration declares is read, in the order it declares them.")
    func readsNames() {
        let configuration = """
            alias.cm commit -m
            alias.co checkout
            alias.lg log --oneline --graph
            """
        #expect(GitAliases.names(in: configuration) == ["cm", "co", "lg"])
    }

    @Test("A line that binds nothing, or binds nothing to a name, is not an alias.")
    func ignoresAnythingElse() {
        #expect(GitAliases.names(in: "user.name Someone\ncore.editor vim").isEmpty)
        #expect(GitAliases.names(in: "alias. commit").isEmpty)
        #expect(GitAliases.names(in: "").isEmpty)
    }
}
