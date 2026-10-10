import Testing
import UttrflowPredict
import MLXLMCommon

@testable import UttrflowLocalModel

/// What the model's reply is allowed to become, decided without loading a model.
@Suite("Completion parsing")
struct CompletionParsingTests {
    @Test("A single-line pass stopped by its token budget offers no candidate.")
    func tokenLimitedPassIsWithheld() {
        let situation = GenerationSituation(application: "Notes")
        let cutOff = MLXCandidateScorer.completions(
            from: .init(
                forgetGeneration: 0, text: "see you at the cafe", stop: .length, written: "", tokens: [],
                logProbabilities: [], bytes: []),
            typed: "see you", asking: .one, in: situation)
        #expect(cutOff.isEmpty)

        let endedNormally = MLXCandidateScorer.completions(
            from: .init(
                forgetGeneration: 0, text: "see you at the cafe", stop: .stop, written: "", tokens: [],
                logProbabilities: [], bytes: []),
            typed: "see you", asking: .one, in: situation)
        #expect(endedNormally == ["see you at the cafe"])
    }

    @Test("An alternatives pass drops only its unterminated line when the token budget ends it.")
    func tokenLimitedAlternativesDropTheirCutLine() {
        let situation = GenerationSituation(application: "Notes")
        let cutOff = MLXCandidateScorer.completions(
            from: .init(
                forgetGeneration: 0, text: "see you at the park\nsee you after the", stop: .length,
                written: "", tokens: [],
                logProbabilities: [], bytes: []),
            typed: "see you", asking: .others(excluding: "see you soon"), in: situation)
        #expect(cutOff == ["see you at the park"])

        let endedOnNewline = MLXCandidateScorer.completions(
            from: .init(
                forgetGeneration: 0, text: "see you at the park\nsee you after the park\n", stop: .length,
                written: "", tokens: [],
                logProbabilities: [], bytes: []),
            typed: "see you", asking: .others(excluding: "see you soon"), in: situation)
        #expect(endedOnNewline == ["see you at the park", "see you after the park"])

        let unparsableCutLine = MLXCandidateScorer.completions(
            from: .init(
                forgetGeneration: 0, text: "see you at the park\nunfinished", stop: .length, written: "",
                tokens: [],
                logProbabilities: [], bytes: []),
            typed: "see you", asking: .others(excluding: "see you soon"), in: situation)
        #expect(unparsableCutLine == ["see you at the park"])
    }

    @Test(
        "An indented line is read against the typed text without its indentation, and keeps it in the answer."
    )
    func indentationIsKept() {
        #expect(CompletionText.parse("    return a + b", typed: "    return ") == ["    return a + b"])
        #expect(CompletionText.parse("  return a + b;", typed: "  return a ") == ["  return a + b;"])
    }

    @Test("Lines that extend what was typed are kept in order, once each, whatever marks the model added.")
    func extendingLinesAreKept() {
        let reply = "```\n1. git checkout main\n- git commit -m\n* git checkout main\ngit c\n```"
        #expect(CompletionText.parse(reply, typed: "git c") == ["git checkout main", "git commit -m"])
    }

    @Test("A line quoting the prompt back is not a completion, however it begins.")
    func promptEchoesAreDropped() {
        let reply = "Notes, field AXTextArea, continue this text:\nnavigate to the settings"
        #expect(CompletionText.parse(reply, typed: "n") == ["navigate to the settings"])
        let headings = """
            on my way. Continue this line:
            on screen around the field: Priya
            on my way, Lines this person wrote here before
            on my way, be there at 7
            """
        #expect(CompletionText.parse(headings, typed: "on my") == ["on my way, be there at 7"])
    }

    @Test("Prompt-marker words in the typed line do not suppress its continuation.")
    func promptMarkerInTypedTextDoesNotSuppressContinuation() {
        #expect(
            CompletionText.parse("Some hints: keep it short", typed: "Some hints:") == [
                "Some hints: keep it short"
            ])
        #expect(CompletionText.parse("Some hints: continue this text", typed: "Some hints:").isEmpty)
    }

    @Test(
        "A line the model repeated without its marks, in another case or spacing, is still read past what was typed."
    )
    func rewrittenEchoesAreStillRead() {
        let typed = "what is the price of MitoActive™  serum"
        let reply = "What is the price of MitoActive serum, and is it in stock?"
        #expect(CompletionText.parse(reply, typed: typed) == [typed + ", and is it in stock?"])
        #expect(CompletionText.continuation(of: "Git Commit -m", past: "git c") == "ommit -m")
        #expect(CompletionText.continuation(of: "svn commit", past: "git c") == nil)
        #expect(CompletionText.continuation(of: "git c", past: "git c") == "")
        #expect(CompletionText.continuation(of: "anything", past: "") == "anything")
        #expect(CompletionText.comparable("A™  b\u{200E}C") == "a bc")
    }

    @Test(
        "Swapped characters and same-word spelling forms are read past; an added letter cannot change the word."
    )
    func echoSlipMustPreserveTheWord() {
        #expect(CompletionText.continuation(of: "don't know", past: "dont") == " know")
        #expect(CompletionText.continuation(of: "the quick fix", past: "teh") == " quick fix")
        #expect(CompletionText.continuation(of: "git commit -m", past: "gitcommit") == " -m")
        #expect(CompletionText.continuation(of: "git  commit -m", past: "git commit") == " -m")
        #expect(CompletionText.continuation(of: "runs fast", past: "run ") == "fast")
        #expect(CompletionText.continuation(of: "receive the parcel", past: "recieve") == " the parcel")
        #expect(CompletionText.continuation(of: "colour scheme", past: "color") == nil)
        #expect(CompletionText.continuation(of: "she is going", past: "he is") == nil)
        #expect(CompletionText.continuation(of: "her is going", past: "he is") == nil)
        #expect(CompletionText.parse("she is going", typed: "he is").isEmpty)
        #expect(CompletionText.parse("don't know\n", typed: "dont") == ["dont know"])
        #expect(CompletionText.parse("The quick fix", typed: "teh") == ["teh quick fix"])
    }

    @Test(
        "A second slip, or a changed last character with nothing typed after it, is another line and not an echo."
    )
    func twoSlipsOrAChangedEndAreNotAnEcho() {
        #expect(CompletionText.continuation(of: "git status", past: "git c") == nil)
        #expect(CompletionText.continuation(of: "do'n't know", past: "dont") == nil)
        #expect(CompletionText.continuation(of: "§§dont know", past: "dont") == nil)
        #expect(
            CompletionText.parse("git status\ngit checkout main", typed: "git c") == ["git checkout main"]
        )
    }

    @Test("A line the model returned unchanged, or with only whitespace added, is nothing to offer.")
    func unchangedLinesAreNothing() {
        #expect(CompletionText.parse("git c\ngit c  ", typed: "git c").isEmpty)
        #expect(
            CompletionText.parse(
                "What is the price of MitoActive serum", typed: "what is the price of MitoActive™ serum"
            ).isEmpty)
    }

    @Test("A completion cannot end a number the person may still be typing")
    func incompleteNumbersAreNotClosedByTheSuggestion() {
        #expect(CompletionText.parse("LIMIT 10 OFFSET 0", typed: "LIMIT 10").isEmpty)
        #expect(CompletionText.parse("LIMIT 5 OFFSET 0", typed: "LIMIT 5").isEmpty)
        #expect(CompletionText.parse("LIMIT 100;", typed: "LIMIT 10") == ["LIMIT 100;"])
        #expect(CompletionText.parse("LIMIT 50;", typed: "LIMIT 5") == ["LIMIT 50;"])
        #expect(CompletionText.parse("LIMIT 10.5;", typed: "LIMIT 10") == ["LIMIT 10.5;"])
        #expect(CompletionText.parse("LIMIT 10e3;", typed: "LIMIT 10") == ["LIMIT 10e3;"])
    }

    @Test("Unsafe control, format, and replacement scalars reject the whole continuation.")
    func unsafeScalarsAreRejected() {
        for scalar in ["\t", "\u{1B}", "\u{200B}", "\u{202E}", "\u{2066}", "\u{FFFD}"] {
            #expect(CompletionText.parse("Thanks for the \(scalar)update", typed: "Thanks for the").isEmpty)
        }
        #expect(
            CompletionText.parse("Thanks for the update", typed: "Thanks for the") == [
                "Thanks for the update"
            ])
    }

    @Test("A continuation that loops on itself is dropped rather than drawn across the screen.")
    func repetitionIsDropped() {
        let looping = "sr" + String(repeating: " -  sr", count: 40)
        #expect(CompletionText.parse(looping + "\nsrc/main.swift", typed: "sr") == ["src/main.swift"])
        #expect(CompletionText.isDegenerate(" - sr - sr - sr - sr - sr - sr"))
        #expect(!CompletionText.isDegenerate(" -l"))
        #expect(!CompletionText.isDegenerate("toring the data in the table for the next run"))
    }

    @Test("A word repeated, or spelled out one letter at a time, is not a continuation.")
    func stutterAndSpelledOutAreDropped() {
        #expect(CompletionText.isDegenerate(" pic pic pic pic pic"))
        #expect(CompletionText.isDegenerate(" a s s p o r t"))
        #expect(!CompletionText.isDegenerate(" a b c"))
        #expect(!CompletionText.isDegenerate(" no no no, not that one"))
        #expect(!CompletionText.isDegenerate(" I want a cup of tea"))
    }

    @Test("A continuation the length of a paragraph is not the rest of a line.")
    func paragraphsAreDropped() {
        let paragraph = String(repeating: "word ", count: 60)
        #expect(CompletionText.isDegenerate(paragraph))
        #expect(CompletionText.parse("st" + paragraph, typed: "st").isEmpty)
    }

    @Test("Nothing is made of one typed character, since a guess about nothing is noise.")
    func oneCharacterIsTooLittle() {
        #expect(MLXCandidateScorer.minimumTypedLength == 2)
        #expect("s".trimmingCharacters(in: .whitespaces).count < MLXCandidateScorer.minimumTypedLength)
        #expect("ls".trimmingCharacters(in: .whitespaces).count >= MLXCandidateScorer.minimumTypedLength)
    }

    @Test(
        "A line is cut where it takes up a part of a screen label, and dropped when nothing of its own is left."
    )
    func copiesOfTheScreenAreCut() {
        let screen =
            "message, Baby busy ho?, 3Septemberat6:41\u{202F}PM, Received from Priya\nYour message, Haan, Sent to Priya, Delivered"
        #expect(
            CompletionText.trimmed(
                "phone pe nahi, 4Septemberat6:42 PM, Received from Priya", typed: "phone", echoing: [screen])
                == "phone pe nahi")
        #expect(
            CompletionText.trimmed("phone, Received from Priya", typed: "phone", echoing: [screen]) == nil
        )
        #expect(
            CompletionText.trimmed("phone pe nahi, Delivered", typed: "phone", echoing: [screen])
                == "phone pe nahi")
        #expect(
            CompletionText.trimmed("phone pe nahi yaar", typed: "phone", echoing: [screen])
                == "phone pe nahi yaar")
        #expect(CompletionText.trimmed("phone pe nahi", typed: "phone", echoing: []) == "phone pe nahi")
        // Quoting the screen in the line's own words is a reply, not a copy of a label.
        #expect(
            CompletionText.trimmed("phone busy ho?", typed: "phone", echoing: [screen])
                == "phone busy ho?")
        #expect(
            CompletionText.trimmed(
                "khana bhi wahi kha lenge", typed: "khana ", echoing: ["Priya: wahi kha lenge?"])
                == "khana bhi wahi kha lenge")
        // A shell reuses a file name and a query a column list from the screen; neither is a label part.
        #expect(
            CompletionText.trimmed(
                "git add Sources/Login/Session.swift", typed: "git add ",
                echoing: ["Sources/Login/Session.swift"])
                == "git add Sources/Login/Session.swift")
        #expect(
            CompletionText.trimmed(
                "INSERT INTO products (id, name, price, stock)", typed: "INSERT INTO products ",
                echoing: ["products: id, name, price, stock"])
                == "INSERT INTO products (id, name, price, stock)")
    }

    @Test("A time or date inside the line is its answer, and only a stamp hung after the line is dropped")
    func onlyATrailingStampIsDropped() {
        #expect(
            CompletionText.trimmed(
                "The meeting is at 10:30, see you there", typed: "The meeting is at", echoing: [])
                == "The meeting is at 10:30, see you there")
        #expect(
            CompletionText.trimmed(
                "Let's meet on Friday, 5 March, at the office", typed: "Let's meet on", echoing: [])
                == "Let's meet on Friday, 5 March, at the office")
        #expect(
            CompletionText.trimmed("The meeting is at 10:30", typed: "The meeting is at", echoing: [])
                == "The meeting is at 10:30")
        #expect(
            CompletionText.trimmed(
                "See you there, 4 September at 6:41 PM", typed: "See you", echoing: [])
                == "See you there")
        #expect(CompletionText.trimmed("ok, 12:46 PM", typed: "ok", echoing: []) == nil)
    }

    @Test(
        "A new word of one or two characters is nothing, while a character that finishes the typed word stays."
    )
    func aStubOfANewWordIsNothing() {
        #expect(CompletionText.trimmed("busy nahi h", typed: "busy nahi", echoing: []) == nil)
        #expect(
            CompletionText.trimmed("busy nahi hoon", typed: "busy nahi", echoing: []) == "busy nahi hoon")
        #expect(CompletionText.trimmed("git add", typed: "git ad", echoing: []) == "git add")
        #expect(CompletionText.trimmed("yes!", typed: "yes", echoing: []) == "yes!")
    }

    @Test(
        "Whether an answer repeated the line is asked of the whole echo, not of its first two characters."
    )
    func anEchoIsReadWholeRatherThanByItsOpening() {
        #expect(CompletionText.echoes("busy nahi hoon bolo", of: "busy nahi"))
        #expect(CompletionText.echoes("- busy nahi hoon", of: "busy nahi"))
        #expect(!CompletionText.echoes("hoon bolo", of: "busy nahi"))
        // The answer drops the line and opens on a character the line opens on, which a prefix cannot tell apart.
        #expect(!CompletionText.echoes("busier tomorrow", of: "busy nahi"))
    }

    @Test(
        "An answer without its echo joins the line only where a boundary says how, never letters against letters."
    )
    func anEchoLessAnswerJoinsOnlyAtABoundary() {
        #expect(CompletionText.joined("busy nahi ", with: "hoon bolo") == "busy nahi hoon bolo")
        #expect(CompletionText.joined("busy nahi", with: " hoon bolo") == "busy nahi hoon bolo")
        #expect(CompletionText.joined("busy nahi ", with: " hoon bolo") == "busy nahi hoon bolo")
        #expect(CompletionText.joined("see you at 8", with: ", then") == "see you at 8, then")
        #expect(CompletionText.joined("hello", with: "\"world\"") == "hello \"world\"")
        #expect(CompletionText.joined("hello", with: "'world'") == "hello 'world'")
        #expect(CompletionText.joined("she said ", with: "\"hello\"") == "she said \"hello\"")
        #expect(CompletionText.joined("she said \"hello ", with: "\"") == "she said \"hello\"")
        #expect(CompletionText.joined("see you ", with: ", then") == "see you, then")
        #expect(CompletionText.joined("see you ", with: ")") == "see you)")
        #expect(CompletionText.joined("don", with: "'t") == "don't")
        #expect(CompletionText.joined("James", with: "'s here") == "James's here")
        #expect(CompletionText.joined("see you", with: "(8pm)") == nil)
        #expect(CompletionText.joined("she said", with: "\"hello\"") == "she said \"hello\"")
        #expect(CompletionText.joined("cost", with: "$5") == nil)
        #expect(CompletionText.joined("see you ", with: "(8pm)") == "see you (8pm)")
        #expect(CompletionText.joined("busy nahi", with: "hoon bolo") == nil)
        #expect(CompletionText.joined("git c", with: "ommit -m") == nil)
        #expect(CompletionText.joined("", with: "hoon") == nil)
        #expect(CompletionText.joined("busy", with: "") == nil)
    }

    @Test("An Apple answer joins ordinary continuations, then refuses model remarks.")
    func appleFallbackRequiresAReadableNonMetaContinuation() {
        let typed = "Thanks for your email "
        let situation = GenerationSituation(application: "Mail")
        #expect(
            CompletionText.modelCompletions(
                from: "I'll send the invoice tomorrow.", typed: typed, echoPolicy: .joinAtBoundary,
                in: situation) == ["Thanks for your email I'll send the invoice tomorrow."]
        )
        #expect(
            CompletionText.modelCompletions(
                from: "I'm sorry, but I can't help with that.", typed: typed,
                echoPolicy: .joinAtBoundary, in: situation
            ).isEmpty)
        #expect(
            CompletionText.modelCompletions(
                from: "Here is the completion: Thanks for your email, I'll send it tomorrow.",
                typed: typed, echoPolicy: .joinAtBoundary, in: situation
            ).isEmpty)
    }

    @Test("Common openings can continue text the model echoed from the field.")
    func echoedTextCanContinueWithCommonOpenings() {
        let situation = GenerationSituation(application: "Mail")
        #expect(
            CompletionText.modelCompletions(
                from: "I'm so sorry about that", typed: "I'm so", echoPolicy: .required,
                in: situation) == ["I'm so sorry about that"])
        #expect(
            CompletionText.modelCompletions(
                from: "Hi Sam, here is the report", typed: "Hi Sam,", echoPolicy: .required,
                in: situation) == ["Hi Sam, here is the report"])
    }

    @Test("Every tabled refusal is refused, with common continuations allowed after an echoed prefix.")
    func modelRemarksRespectWhetherTheyContinueEchoedTypedText() {
        let typed = "Thanks for your email "
        let situation = GenerationSituation(application: "Mail")
        for opening in CompletionText.rejectedOpenings {
            #expect(
                CompletionText.modelCompletions(
                    from: opening.phrase + "; the rest follows.", typed: typed,
                    echoPolicy: .joinAtBoundary, in: situation
                ).isEmpty,
                "Echo-less reply: \(opening.phrase)")
            let echoed = typed + opening.phrase + "; the rest follows."
            #expect(
                CompletionText.modelCompletions(
                    from: echoed, typed: typed, echoPolicy: .required, in: situation
                ).isEmpty == opening.rejectedAfterTypedEcho,
                "Echoed reply: \(opening.phrase)")
        }
    }

    @Test("The MLX candidate path refuses an echoed answer that starts with a refusal.")
    func mlxGeneratorRefusesEchoedRefusal() {
        let typed = "Thanks for your email "
        let run = MLXCandidateScorer.Run(
            forgetGeneration: 0, text: "I'm sorry, but I can't help with that.", stop: .stop,
            written: typed, tokens: [], logProbabilities: [], bytes: [])
        #expect(
            MLXCandidateScorer.completions(
                from: run, typed: typed, asking: .one, in: GenerationSituation(application: "Mail")
            ).isEmpty)
    }

    @Test("A line the model wrote in another script is dropped, wherever in the line the script appears.")
    func nonLatinLinesAreDropped() {
        let reply = "kal मिलते हैं\nkal milte hain\nkal 见\nkal pakka, café mein"
        #expect(CompletionText.parse(reply, typed: "kal ") == ["kal milte hain", "kal pakka, café mein"])
        #expect(CompletionText.parse("नहीं जाना", typed: "नहीं ") == [])
    }
}

@Suite("What a suggestion may never copy")
struct ContextNeverCopiedTests {
    @Test("The screen and the text before the line are both context never to copy")
    func screenAndPrecedingAreContext() {
        let situation = GenerationSituation(
            application: "Mail", preceding: "Hi Sam,", windowTitle: "Re: invoice",
            surroundings: "Could you share the invoice?", recentLines: ["Kind regards,"])
        #expect(
            CompletionText.contextNeverCopied(in: situation) == ["Could you share the invoice?", "Hi Sam,"])
    }

    @Test("With nothing on screen and nothing before the line there is no context, whatever the person wrote")
    func noScreenIsNoContext() {
        let situation = GenerationSituation(
            application: "Terminal", windowTitle: "shell", recentLines: ["git status"])
        #expect(CompletionText.contextNeverCopied(in: situation).isEmpty)
        #expect(
            CompletionText.contextNeverCopied(in: GenerationSituation(application: "Notes", preceding: "one"))
                == ["one"])
        #expect(
            CompletionText.contextNeverCopied(
                in: GenerationSituation(application: "Notes", surroundings: "two"))
                == ["two"])
    }

    @Test("A line the typed text already holds is kept whole, even where the screen repeats a label of it")
    func typedTextIsNeverCut() {
        let situation = GenerationSituation(
            application: "Messages", surroundings: "phone, Received from Priya")
        let context = CompletionText.contextNeverCopied(in: situation)
        #expect(
            CompletionText.trimmed(
                "phone, Received from Priya, ok", typed: "phone, Received from Priya", echoing: context)
                == "phone, Received from Priya, ok")
        #expect(
            CompletionText.trimmed("phone pe nahi, Received from Priya", typed: "phone", echoing: context)
                == "phone pe nahi")
    }
}

/// A chat whose last message a reply could echo, with this person's own short replies.
private let deckChat = GenerationSituation(
    application: "Chat", field: "Message", windowTitle: "Sam",
    surroundings: """
        Sam: morning, quick one
        Me: hey, what's up
        Sam: the client call moved to 3
        Sam: Can you send the deck by Friday?
        """,
    recentLines: ["hey, what's up", "on it", "sounds good", "will do"], isMultiline: true)

@Suite("A suggestion never copies a run of screen words")
struct CopiedRunTests {
    @Test("A reply that repeats the other person's last message is refused on either model's path")
    func anEchoedMessageIsRefused() {
        let context = CompletionText.contextNeverCopied(in: deckChat)
        #expect(
            CompletionText.copiesContext(
                "Can you send the deck by Friday?", typed: "Can you", context: context, ownLines: []))
        #expect(
            CompletionText.finished(["Can you send the deck by Friday?"], typed: "Can you", in: deckChat)
                .isEmpty)
        // A word the typed text only began still counts as the model's, so a mid-word cut is no way round it.
        #expect(
            CompletionText.finished(["Can you send the deck by Friday?"], typed: "Can you se", in: deckChat)
                .isEmpty)
    }

    @Test("Fewer than five words in a row, or words the person typed themselves, are not a copy")
    func shortRunsAndTypedWordsAreKept() {
        let context = CompletionText.contextNeverCopied(in: deckChat)
        #expect(
            !CompletionText.copiesContext(
                "Can you send the deck later", typed: "Can you", context: context, ownLines: []))
        #expect(
            !CompletionText.copiesContext(
                "Can you send the deck by Friday?", typed: "Can you send the deck", context: context,
                ownLines: []))
        #expect(
            CompletionText.finished(["yes I can send the deck by monday"], typed: "yes I", in: deckChat)
                == ["yes I can send the deck by monday"])
    }

    @Test("A run the person has written here before is theirs to repeat")
    func aRunInTheirOwnLinesIsKept() {
        let context = CompletionText.contextNeverCopied(in: deckChat)
        #expect(
            !CompletionText.copiesContext(
                "Can you send the deck by Friday?", typed: "Can you", context: context,
                ownLines: ["can you send the deck by friday"]))
    }

    @Test("A command may reuse a path the screen shows, however many words it splits into")
    func aCommandMayReuseTheScreen() {
        let shell = GenerationSituation(
            application: "Terminal", preceding: "$ ls projects/uttrflow/app/Sources/Login/Session",
            recentLines: [
                "git commit -m 'fix: ship it'", "ls -la ~/src/*.swift", "docker compose -f ./a.yml up -d",
            ])
        let line = "cd projects/uttrflow/app/Sources/Login/Session"
        #expect(CompletionText.finished([line], typed: "cd ", in: shell) == [line])
    }

    @Test("A run is read within one line of the screen, never across two")
    func runsDoNotCrossLines() {
        #expect(
            !CompletionText.copiesContext(
                "ok we moved to 3 sam the deck", typed: "ok", context: ["we moved to 3\nSam: the deck"],
                ownLines: []))
    }
}

@Suite("A suggestion ends where its line ends")
struct FirstSentenceTests {
    @Test("A reply that runs into a second sentence is ended at the first")
    func aReplyEndsAtItsFirstSentence() {
        let raw = "ok sounds good, see you at 3. Let me know if anything changes and I will update the doc."
        #expect(
            CompletionText.finished([raw], typed: "ok sounds g", in: deckChat) == [
                "ok sounds good, see you at 3."
            ])
        #expect(CompletionText.firstSentence(of: "sure! on my way", typed: "su") == "sure!")
        #expect(CompletionText.firstSentence(of: "is it done?? I need it", typed: "is") == "is it done??")
        #expect(
            CompletionText.firstSentence(of: "she said \"go.\" Then left", typed: "she") == "she said \"go.\""
        )
    }

    @Test("A stop inside a number, an address, an abbreviation or an ellipsis is no sentence end")
    func stopsThatEndNothing() {
        for line in [
            "meet at 5.30 near the gate", "see example.com for details", "bring snacks, e.g. chips and dip",
            "ask Dr. Rao about it", "hmm... maybe later", "call J. Smith first",
        ] {
            #expect(CompletionText.firstSentence(of: line, typed: String(line.prefix(4))) == line, "\(line)")
        }
    }

    @Test("An abbreviation ends a sentence before an uppercase word, except a title before a name")
    func abbreviationsCanEndSentences() {
        #expect(
            CompletionText.firstSentence(
                of: "The call is at 10 a.m. Please bring the slides.", typed: "The call is at 10")
                == "The call is at 10 a.m.")
        #expect(
            CompletionText.firstSentence(
                of: "Let's meet at 6 p.m. We can review the deck.", typed: "Let's meet at 6")
                == "Let's meet at 6 p.m.")
        #expect(
            CompletionText.firstSentence(
                of: "Bring pens, paper, etc. We start at nine.", typed: "Bring pens")
                == "Bring pens, paper, etc.")
        #expect(
            CompletionText.firstSentence(of: "I got an A. It was hard.", typed: "I got an") == "I got an A.")
        #expect(
            CompletionText.firstSentence(of: "Mr. Smith will join us.", typed: "Mr")
                == "Mr. Smith will join us.")
        #expect(
            CompletionText.firstSentence(of: "Please ask Dr. Rao tomorrow.", typed: "Please ask")
                == "Please ask Dr. Rao tomorrow.")
        #expect(
            CompletionText.firstSentence(of: "Bring e.g. this example along.", typed: "Bring")
                == "Bring e.g. this example along.")
    }

    @Test("A sentence end the person typed is theirs, and the line goes on to the next")
    func aTypedStopIsNotCut() {
        #expect(
            CompletionText.firstSentence(of: "Done. Sending it now. Thanks", typed: "Done. S")
                == "Done. Sending it now.")
    }

    @Test("A command keeps every clause, since a full stop there is no sentence end")
    func aCommandIsNotCut() {
        let shell = GenerationSituation(
            application: "Terminal", preceding: "$ git status",
            recentLines: [
                "git commit -m 'fix: ship it'", "ls -la ~/src/*.swift", "docker compose -f ./a.yml up -d",
            ])
        #expect(
            CompletionText.finished(["git commit -m 'fix. ship it. now'"], typed: "git commit", in: shell)
                == ["git commit -m 'fix. ship it. now'"])
    }
}

@Suite("A suggestion is held to the length this person writes")
struct ContinuationLengthTests {
    @Test("In a chat of short replies a long continuation is refused, and a short one kept")
    func aLongReplyIsRefused() {
        let long =
            "sounds good, I will have the whole thing ready well before the call and send it across to everyone"
        #expect(CompletionText.finished([long], typed: "sou", in: deckChat).isEmpty)
        #expect(CompletionText.finished(["sounds good"], typed: "sou", in: deckChat) == ["sounds good"])
    }

    @Test("With no history the register's own limit holds, not one limit for every field")
    func theRegisterSetsTheLimitWithoutHistory() {
        let notes = GenerationSituation(application: "Notes", isMultiline: true)
        let line = "The plan is " + String(repeating: "longer and ", count: 12) + "done"
        #expect(line.count - 4 > 80 && line.count - 4 <= 160)
        #expect(CompletionText.finished([line], typed: "The ", in: notes) == [line])
        let chat = GenerationSituation(
            application: "Chat", field: "Message",
            surroundings: "Sam: hi\nMe: hey\nSam: are you around\nSam: call?", isMultiline: true)
        #expect(CompletionText.finished([line], typed: "The ", in: chat).isEmpty)
    }

    @Test("Two lines that finish the same are offered once")
    func finishedLinesAreOfferedOnce() {
        #expect(
            CompletionText.finished(["sure, on it. Later", "sure, on it. Soon"], typed: "sure", in: deckChat)
                == ["sure, on it."])
    }
}

@Suite("A sign-off is signed only with a name the person wrote", .bug(id: 5966))
struct SignOffTests {
    @Test("a closing word inside ordinary prose does not begin a signature")
    func embeddedClosingStaysInProse() {
        #expect(
            SignOff.unsigned(
                "Hi Sam, thanks, Sarah is coming", typed: "Hi Sam, ", ownLines: [])
                == "Hi Sam, thanks, Sarah is coming")
        #expect(
            SignOff.unsigned("I said, thanks, Priya will drive", typed: "I said, ", ownLines: [])
                == "I said, thanks, Priya will drive")
    }

    @Test("newline closings and lowercase signatures keep their distinct behavior")
    func newlineAndLowercaseSignatures() {
        #expect(
            SignOff.unsigned("Kind regards,\nJohn", typed: "Kind reg", ownLines: [])
                == "Kind regards,")
        #expect(SignOff.unsigned("Thanks\nJohn", typed: "Thanks\n", ownLines: []) == "Thanks\nJohn")
        #expect(SignOff.unsigned("thanks, john", typed: "", ownLines: []) == "thanks, john")
        #expect(
            SignOff.unsigned("Got it.\nThanks, Sarah is coming", typed: "Got it.\n", ownLines: [])
                == "Got it.\nThanks,")
        #expect(
            SignOff.unsigned("See you then. Thanks, Sarah", typed: "See you then. ", ownLines: [])
                == "See you then. Thanks,")
    }

    @Test("A name followed by a farewell, a title or more names is cut from a prose suggestion")
    func trailingWordsDoNotHideAnInventedName() {
        let mail = GenerationSituation(application: "Mail", isMultiline: true)
        for (typed, line) in [
            ("Thanks,", "Thanks, Sam. Talk soon"),
            ("Best,", "Best, Sam from support"),
            ("Kind regards,", "Kind regards, Dr. Alex J. Morgan"),
            ("Best regards,", "Best regards, Alex Morgan, Head of Sales"),
        ] {
            #expect(CompletionText.finished([line], typed: typed, in: mail).isEmpty, "\(line)")
        }
    }

    @Test("A name followed by lowercased trailing prose passes when the person wrote the name")
    func writtenNameWithTrailingWordsPasses() {
        #expect(
            SignOff.unsigned("Thanks, Sam from support", typed: "Thanks,", ownLines: ["Cheers, Sam"])
                == "Thanks, Sam from support")
    }

    @Test("A closing the person typed is not signed with the sender's name")
    func theSendersNameIsNotSigned() {
        let own = ["Please find the document attached.", "Kind regards,"]
        #expect(
            SignOff.unsigned("Kind regards, Sam", typed: "Kind regards,", ownLines: own)
                == nil)
        #expect(SignOff.unsigned("Thanks, Sam.", typed: "Thanks, ", ownLines: own) == nil)
        #expect(SignOff.unsigned("best,  Sam", typed: "best,", ownLines: []) == nil)
    }

    @Test("A closing still being typed is finished without the sender's name after it")
    func theClosingIsKept() {
        #expect(
            SignOff.unsigned("Kind regards, Sam", typed: "Kind reg", ownLines: [])
                == "Kind regards,")
    }

    @Test("A name the person has written in their own lines is theirs to sign with")
    func theirOwnNameIsKept() {
        #expect(
            SignOff.unsigned(
                "Kind regards, Alex", typed: "Kind regards,", ownLines: ["Cheers, Alex"])
                == "Kind regards, Alex")
    }

    @Test("A name found nowhere the person wrote is cut back to the closing")
    func anInventedNameIsCut() {
        #expect(SignOff.unsigned("Best regards, David", typed: "Best regards,", ownLines: []) == nil)
        #expect(SignOff.unsigned("Best regards, David", typed: "Best", ownLines: []) == "Best regards,")
        #expect(
            SignOff.unsigned("Thanks, Sam Collins", typed: "Thanks,", ownLines: ["Cheers, Sam"]) == nil)
        #expect(
            SignOff.unsigned("Thanks, Sam Collins", typed: "Thanks, Sam", ownLines: ["Collins here"])
                == "Thanks, Sam Collins")
    }

    @Test("a lowercase verb does not establish the same word as a signature name")
    func aLowercaseVerbDoesNotEstablishAName() {
        let own = ["I will send it Monday"]
        #expect(SignOff.unsigned("Best,\nWill", typed: "Best", ownLines: own) == "Best,")
        #expect(SignOff.unsigned("Best,\nWill", typed: "Best,", ownLines: own) == nil)
    }

    @Test("common closings still cut an invented signature")
    func commonClosingsCutInventedNames() {
        for closing in ["Respectfully", "Cordially", "Love", "Talk soon"] {
            #expect(
                SignOff.unsigned("\(closing), Will", typed: closing, ownLines: []) == "\(closing),",
                "\(closing)")
        }
    }

    @Test("A recipient name in the typed text is not treated as the sender's signature")
    func aRecipientNameDoesNotBecomeTheSendersName() {
        #expect(
            SignOff.unsigned(
                "Thanks Rahul, regards, Rahul", typed: "Thanks Rahul, ", ownLines: [])
                == "Thanks Rahul, regards,")
    }

    @Test("A closing after a greeting or sentence is not signed with an invented name")
    func anInventedNameAfterEarlierCommasIsCut() {
        #expect(
            SignOff.unsigned("Hi Sam, sure. Best, Raj", typed: "", ownLines: [])
                == "Hi Sam, sure. Best,")
        #expect(
            SignOff.unsigned("Hi Sam, Best, Raj", typed: "", ownLines: [])
                == "Hi Sam, Best,")
    }

    @Test("Words after a comma that are not a closing's signature are left alone")
    func otherLinesAreLeftAlone() {
        #expect(
            SignOff.unsigned("Thanks, see you tomorrow", typed: "Thanks,", ownLines: [])
                == "Thanks, see you tomorrow")
        #expect(
            SignOff.unsigned("Hi Sam, could you share", typed: "Hi", ownLines: [])
                == "Hi Sam, could you share")
        #expect(SignOff.unsigned("Hi, Sam", typed: "Hi,", ownLines: []) == "Hi, Sam")
        #expect(
            SignOff.unsigned("Kind regards,", typed: "Kind", ownLines: [])
                == "Kind regards,")
        #expect(
            SignOff.unsigned("Kind regards", typed: "Kind", ownLines: [])
                == "Kind regards")
        #expect(
            SignOff.unsigned(
                "Thanks, Sam Could You Share", typed: "Thanks,", ownLines: [])
                == "Thanks, Sam Could You Share")
    }

    @Test("A signature partly on screen and partly made up is cut")
    func aPartlyInventedSignatureIsCut() {
        #expect(SignOff.unsigned("Thanks, Sam Rivers", typed: "Thanks,", ownLines: []) == nil)
    }
}
