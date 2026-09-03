import Testing

@testable import UttrflowPredict

@Suite("What accepting actually does to the field")
struct AcceptanceTests {
    @Test("A suggestion that continues what was typed replaces none of it.")
    func aContinuationReplacesNothing() throws {
        let edit = try #require(Acceptance.edit(accepting: "git commit", after: "git com"))

        #expect(edit.replaced.isEmpty)
        #expect(edit.replacedCount == 0)
        #expect(edit.isReplacement == false)
        #expect(edit.inserted == "mit")
    }

    @Test("An empty field takes the whole suggestion and gives up nothing.")
    func everythingFromNothing() throws {
        let edit = try #require(Acceptance.edit(accepting: "git commit", after: ""))

        #expect(edit.replacedCount == 0)
        #expect(edit.inserted == "git commit")
    }

    @Test("A suggestion already fully typed asks for no edit at all.")
    func nothingLeftToDo() {
        #expect(Acceptance.edit(accepting: "git commit", after: "git commit") == nil)
        #expect(Acceptance.edit(accepting: "", after: "") == nil)
    }

    @Test("A fuzzy match replaces the characters it disagrees with, and keeps the ones it does not.")
    func fuzzyMatchReplacesTheTypo() throws {
        let edit = try #require(Acceptance.edit(accepting: "git commit -m", after: "gti c"))

        #expect(edit.replaced == "ti c")
        #expect(edit.replacedCount == 4)
        #expect(edit.isReplacement)
        #expect(edit.inserted == "it commit -m")
    }

    @Test("A verified correction replaces only the wrong character.")
    func correctionReplacesTheWrongCharacter() throws {
        let edit = try #require(Acceptance.edit(accepting: "git commit", after: "git comi"))

        #expect(edit.replaced == "i")
        #expect(edit.inserted == "mit")
    }

    @Test("A difference in case is a difference, so the miscased character is replaced too.")
    func caseIsPartOfTheAgreement() throws {
        let edit = try #require(Acceptance.edit(accepting: "git commit", after: "Git com"))

        #expect(edit.replaced == "Git com")
        #expect(edit.inserted == "git commit")
    }

    @Test("A suggestion sharing nothing with what was typed replaces all of it and no more.")
    func sharingNothingReplacesExactlyWhatWasTyped() throws {
        let edit = try #require(Acceptance.edit(accepting: "git commit", after: "svn ci"))

        #expect(edit.replaced == "svn ci")
        #expect(edit.inserted == "git commit")
    }

    @Test("A suggestion shorter than what was typed only takes characters back.")
    func aShorterSuggestionOnlyDeletes() throws {
        let edit = try #require(Acceptance.edit(accepting: "git", after: "git commit"))

        #expect(edit.replacedCount == 7)
        #expect(edit.inserted.isEmpty)
    }

    @Test("What is replaced is always a tail of what the user typed, so nothing else can be reached.")
    func neverReachesPastWhatWasTyped() {
        let typings = ["", "g", "gti c", "Git com", "git commit", "🚀 launch", "café"]
        let suggestions = ["", "git commit", "git commit -m", "🚀 launch now", "cafe", "x"]

        for typed in typings {
            for suggestion in suggestions {
                guard let edit = Acceptance.edit(accepting: suggestion, after: typed) else {
                    continue
                }
                #expect(edit.replacedCount <= typed.count)
                #expect(typed.hasSuffix(edit.replaced))
                #expect(String(typed.dropLast(edit.replacedCount)) + edit.inserted == suggestion)
            }
        }
    }

    @Test("The line is the whole of what may be replaced, so the lines above it are never reached.")
    func aReplacementNeverLeavesTheLine() throws {
        let line = "The qui"
        let continuing = try #require(Acceptance.edit(accepting: "The quick brown fox", after: line))
        #expect(continuing.replaced.isEmpty)

        let disagreeing = try #require(Acceptance.edit(accepting: "A slow badger", after: line))
        #expect(disagreeing.replacedCount == line.count)
        #expect(disagreeing.applied(to: line) == "A slow badger")
    }

    @Test("The count is in characters, so an emoji in the field is one press of Delete and not two.")
    func countedInCharacters() throws {
        let edit = try #require(Acceptance.edit(accepting: "🚀 launch now", after: "🚀 launch"))
        #expect(edit.replacedCount == 0)
        #expect(edit.inserted == " now")

        let replacing = try #require(Acceptance.edit(accepting: "🎉 party", after: "🚀 launch"))
        #expect(replacing.replacedCount == 8)
    }

    @Test("An edit says what the line becomes, which is what the surface can draw ahead of Tab.")
    func anEditSaysWhatTheLineBecomes() throws {
        let appending = try #require(Acceptance.edit(accepting: "git commit", after: "git com"))
        #expect(appending.applied(to: "git com") == "git commit")

        let replacing = try #require(Acceptance.edit(accepting: "git commit -m", after: "gti c"))
        #expect(replacing.applied(to: "gti c") == "git commit -m")

        let deleting = try #require(Acceptance.edit(accepting: "git", after: "git commit"))
        #expect(deleting.applied(to: "git commit") == "git")
    }

    @Test("A suggestion carries its own edit, so what is drawn and what is done are one answer.")
    func theSuggestionAnswersForItself() throws {
        #expect(Suggestion.silent.edit(after: "git com") == nil)
        #expect(Suggestion.minimised.edit(after: "git com") == nil)

        let certain = try #require(Suggestion.certain("git commit").edit(after: "git com"))
        #expect(certain.inserted == "mit")

        let choice = try #require(
            Suggestion.choice(leader: "git commit", others: ["git checkout"])
                .edit(after: "gti c"))
        #expect(choice.replaced == "ti c")
        #expect(choice.inserted == "it commit")
    }
}
