import Testing

@testable import UttrflowContext

@Suite("What a terminal line holds once the shell prompt is taken off it")
struct ShellPromptTests {
    @Test("A default zsh prompt is taken off, hostname and all.")
    func zshDefaultPrompt() {
        #expect(
            ShellPrompt.input(in: "user@host experiments % git status")
                == "git status")
    }

    @Test("A virtualenv in front of the prompt is part of the prompt.")
    func virtualenvPrefix() {
        #expect(
            ShellPrompt.input(
                in: "(experiments) user@host experiments % sudo") == "sudo")
    }

    @Test("A bash prompt ends at the dollar that follows the path.")
    func bashPrompt() {
        #expect(ShellPrompt.input(in: "user@host:~/dir$ git status") == "git status")
    }

    @Test("An oh-my-zsh prompt ends at its git marker, not at the arrow that starts it.")
    func ohMyZshPrompt() {
        #expect(ShellPrompt.input(in: "➜  uttrflow git:(main) ✗ git status") == "git status")
        #expect(ShellPrompt.input(in: "➜  uttrflow git:(main) ✔ git status") == "git status")
    }

    @Test("An arrow prompt is taken off in a clean repository and outside one, where it draws no git marker.")
    func arrowPromptWithoutAMarker() {
        #expect(ShellPrompt.input(in: "➜  uttrflow git:(main) git status") == "git status")
        #expect(ShellPrompt.input(in: "➜  uttrflow git:(feature/login) git sta") == "git sta")
        #expect(ShellPrompt.input(in: "➜  Downloads ls -la") == "ls -la")
        #expect(ShellPrompt.input(in: "  ➜  Downloads ls -la") == "ls -la")
        #expect(ShellPrompt.input(in: "➜  uttrflow git:(main) ") == "")
        #expect(ShellPrompt.input(in: "➜  Downloads ") == "")
        #expect(ShellPrompt.input(in: "➜  uttrflow git:(main) echo 50% done") == "echo 50% done")
        #expect(ShellPrompt.input(in: "➜  uttrflow hg:(default) ✗ hg status") == "hg status")
    }

    @Test("An arrow anywhere but the start of the line is part of the command.")
    func anArrowInsideACommandIsNotAPrompt() {
        #expect(ShellPrompt.input(in: "echo ➜  done") == "echo ➜  done")
        #expect(ShellPrompt.input(in: "user@host:~/dir$ echo ➜  done") == "echo ➜  done")
        #expect(ShellPrompt.input(in: "➜ ls") == "➜ ls")
    }

    @Test("A root prompt is a hash with nothing in front of it.")
    func rootPrompt() {
        #expect(ShellPrompt.input(in: "# apt update") == "apt update")
        #expect(ShellPrompt.input(in: "root@host:~# apt update") == "apt update")
    }

    @Test("recognises dollar and root prompts with whitespace before their marker")
    func spacedDollarAndRootPrompts() {
        #expect(ShellPrompt.input(in: "~/proj $ ls") == "ls")
        #expect(ShellPrompt.input(in: "user@host ~/p $ git st") == "git st")
        #expect(ShellPrompt.input(in: "/ # ls") == "ls")
        #expect(ShellPrompt.input(in: "bash-5.1# ls") == "ls")
        #expect(ShellPrompt.input(in: "sh-4.2# ls") == "ls")
        #expect(ShellPrompt.input(in: "host# ls") == "ls")
        #expect(ShellPrompt.input(in: "echo 5 $ ") == "echo 5 $ ")
    }

    @Test("A python prompt is a run of chevrons.")
    func pythonPrompt() {
        #expect(ShellPrompt.input(in: ">>> import os") == "import os")
        #expect(ShellPrompt.input(in: "> require('os')") == "require('os')")
    }

    @Test("Interactive database and language prompts leave only the typed command.")
    func interactiveShellPrompts() {
        let examples = [
            ("mysql> select 1", "select 1"),
            ("sqlite> .tables", ".tables"),
            ("irb(main):001> puts 1", "puts 1"),
            ("psql (db)> \\d", "\\d"),
            ("mongosh> db.collection.find()", "db.collection.find()"),
            ("test> db.collection.find()", "db.collection.find()"),
            ("> console.log('ready')", "console.log('ready')"),
            (">>> print('ready')", "print('ready')"),
        ]

        for (line, expected) in examples {
            #expect(ShellPrompt.input(in: line) == expected, "did not remove prompt from: \(line)")
        }
    }

    @Test("A spaced command redirection is not a named REPL prompt.")
    func namedPromptWithSpacedRedirectionIsNotRemoved() {
        #expect(ShellPrompt.input(in: "mysql > output.txt") == "mysql > output.txt")
        #expect(ShellPrompt.input(in: "test > output.txt") == "test > output.txt")
    }

    @Test("A database prompt ends at the hash or the chevron its equals sign leads to.")
    func databasePrompt() {
        #expect(ShellPrompt.input(in: "uttrflow=# select") == "select")
        #expect(ShellPrompt.input(in: "uttrflow=> select") == "select")
    }

    @Test("Starship prompt glyphs end a prompt after themed path segments.")
    func starshipPromptGlyphs() {
        #expect(
            ShellPrompt.input(in: "~/code/uttrflow-swift on \u{e0a0} main [!] via \u{f0e7} v20 ❯ git status")
                == "git status")
        #expect(ShellPrompt.input(in: "~/code/uttrflow-swift on main ➜ git status") == "git status")
        #expect(ShellPrompt.input(in: "~/code/uttrflow-swift on main ➤ git status") == "git status")
        #expect(ShellPrompt.input(in: "~/code/uttrflow-swift \u{e0b0} git status") == "git status")
    }

    @Test("Nushell and PowerShell path prompts end at their directory chevron.")
    func nushellAndPowerShellPathPrompts() {
        #expect(ShellPrompt.input(in: "~/code/uttrflow-swift> git status") == "git status")
        #expect(ShellPrompt.input(in: "~/code/uttrflow-swift\n> git status") == "git status")
        #expect(ShellPrompt.input(in: "PS /Users/dev/project> git status") == "git status")
        #expect(
            ShellPrompt.input(in: #"PS /Users/dev/project> Write-Output `"hello ❯ world`""#)
                == #"Write-Output `"hello ❯ world`""#)
        #expect(ShellPrompt.input(in: "PS /Users/dev/one`>two> Get-Location") == "Get-Location")
    }

    @Test("A directory-looking command still keeps its spaced redirection.")
    func directoryRedirectionIsNotANushellPrompt() {
        #expect(ShellPrompt.input(in: "echo / > file") == "echo / > file")
        #expect(ShellPrompt.input(in: "/usr/bin/echo > file") == "/usr/bin/echo > file")
    }

    @Test("A terminator with nothing in front of it is a prompt in its own right.")
    func aBarePromptIsStillAPrompt() {
        #expect(ShellPrompt.input(in: "% ls") == "ls")
        #expect(ShellPrompt.input(in: "$ ls") == "ls")
        #expect(ShellPrompt.input(in: "❯ ls") == "ls")
    }

    @Test("A line with no prompt on it at all comes back exactly as it went in.")
    func noPromptIsUntouched() {
        let continuation = "    --verbose --output result.txt"
        #expect(ShellPrompt.input(in: continuation) == continuation)
        #expect(ShellPrompt.input(in: "git status") == "git status")
        #expect(ShellPrompt.input(in: "") == "")
    }

    @Test("A prompt with nothing typed after it yields nothing, so nothing is captured.")
    func anEmptyPromptYieldsNothing() {
        #expect(ShellPrompt.input(in: "user@host experiments % ").isEmpty)
        #expect(ShellPrompt.input(in: "user@host experiments %").isEmpty)
        #expect(ShellPrompt.input(in: "user@host:~/dir$").isEmpty)
        #expect(ShellPrompt.input(in: ">>>").isEmpty)
    }

    @Test("A percentage inside a command is not a prompt, whether or not a prompt precedes it.")
    func aPercentageIsNotAPrompt() {
        #expect(ShellPrompt.input(in: #"echo "50% done""#) == #"echo "50% done""#)
        #expect(ShellPrompt.input(in: "echo 50% done") == "echo 50% done")
        #expect(
            ShellPrompt.input(in: #"user@host experiments % echo "50% done""#)
                == #"echo "50% done""#)
    }

    @Test("A spaced modulo operator is not a zsh prompt.")
    func moduloOperatorIsNotAPrompt() {
        #expect(ShellPrompt.input(in: "expr 10 % 3") == "expr 10 % 3")
        #expect(ShellPrompt.input(in: "let x=7 % 2") == "let x=7 % 2")
        #expect(ShellPrompt.input(in: "bc <<< 7 % 2") == "bc <<< 7 % 2")
        #expect(ShellPrompt.input(in: "user@host experiments % expr 10 % 3") == "expr 10 % 3")
        #expect(ShellPrompt.input(in: "user@host % expr 10 % 3") == "expr 10 % 3")
        #expect(ShellPrompt.input(in: "zsh % expr 10 % 3") == "expr 10 % 3")
    }

    @Test("A dollar inside a command is not a prompt, whether quoted or expanding a name.")
    func aDollarIsNotAPrompt() {
        #expect(ShellPrompt.input(in: #"git commit -m "fix: 100$""#) == #"git commit -m "fix: 100$""#)
        #expect(ShellPrompt.input(in: "awk '{print $1}'") == "awk '{print $1}'")
        #expect(
            ShellPrompt.input(in: "user@host:~/dir$ awk '{print $1}'") == "awk '{print $1}'")
        #expect(
            ShellPrompt.input(in: #"user@host:~/dir$ git commit -m "fix: 100$""#)
                == #"git commit -m "fix: 100$""#)
    }

    @Test("A redirection is not a prompt, however much of a prompt stands in front of it.")
    func aRedirectionIsNotAPrompt() {
        #expect(ShellPrompt.input(in: "echo hi > file") == "echo hi > file")
        #expect(ShellPrompt.input(in: "user@host:~/dir$ echo hi > file") == "echo hi > file")
        #expect(ShellPrompt.input(in: "grep foo file.txt> results.txt") == "grep foo file.txt> results.txt")
        #expect(ShellPrompt.input(in: "cmd 2> error.log") == "cmd 2> error.log")
        #expect(ShellPrompt.input(in: "cmd &> both.log") == "cmd &> both.log")
    }

    @Test("A fish shell default prompt ends after the home marker, not before it.")
    func fishDefaultPrompt() {
        #expect(ShellPrompt.input(in: "user@host ~> git status") == "git status")
        #expect(ShellPrompt.input(in: "user@host ~/projects> git status") == "git status")
    }

    @Test("A fish shell vi-mode prompt is also taken off, including the mode indicator.")
    func fishViModePrompt() {
        #expect(ShellPrompt.input(in: "[I] user@host ~> git status") == "git status")
    }

    @Test("A trailing comment is not a root prompt.")
    func aCommentIsNotAPrompt() {
        #expect(ShellPrompt.input(in: "echo hi # note") == "echo hi # note")
        #expect(ShellPrompt.input(in: "user@host:~/dir$ echo hi # note") == "echo hi # note")
    }

    @Test("An at sign earlier in a command does not make its trailing comment a root prompt.")
    func anEarlierAtSignLeavesACommentAlone() {
        let quoted = #"git commit -m "fix bug reported by foo@example.com" # needs review"#
        #expect(ShellPrompt.input(in: quoted) == quoted)
        #expect(ShellPrompt.input(in: "ssh user@host # jump box") == "ssh user@host # jump box")
        #expect(
            ShellPrompt.input(in: "[root@host ~]# ssh user@host # jump box") == "ssh user@host # jump box")
    }

    @Test("An unclosed command substitution cannot supply root-prompt evidence.")
    func anUnclosedSubstitutionIsNotARootPrompt() {
        let line = "echo $(printf user@host# apt update"
        #expect(ShellPrompt.input(in: line) == line)
        #expect(
            ShellPrompt.input(in: "echo $(printf user@host# apt update) # note")
                == "echo $(printf user@host# apt update) # note")
    }

    @Test("Nested and quoted command substitutions do not supply root-prompt evidence.")
    func nestedSubstitutionsAreNotRootPrompts() {
        let nested = "echo $(printf $(printf user@host# apt update)"
        #expect(ShellPrompt.input(in: nested) == nested)
        let quoted = #"echo "$(printf user@host# apt update)" # note"#
        #expect(ShellPrompt.input(in: quoted) == quoted)
    }

    @Test("A genuine root prompt after a closed substitution still ends the prompt.")
    func rootPromptAfterClosedSubstitution() {
        #expect(ShellPrompt.input(in: "echo $(printf ready) root@host# apt update") == "apt update")
    }

    @Test("An escaped quote does not open one, so a later prompt character is still seen.")
    func anEscapedQuoteOpensNothing() {
        #expect(ShellPrompt.input(in: #"user\@host:~/dir$ ls"#) == "ls")
        #expect(ShellPrompt.input(in: #"echo \" 50% done"#) == #"echo \" 50% done"#)
    }

    @Test("An escaped quote inside a double-quoted argument keeps the argument quoted.")
    func anEscapedQuoteInsideAQuoteStaysQuoted() {
        let line = #"git commit -m "fixed \"a@b# now\" done" # note"#
        #expect(ShellPrompt.input(in: line) == line)
        #expect(ShellPrompt.input(in: #"$ echo 'a\' # note"#) == #"echo 'a\' # note"#)
    }

    @Test("A quote left open swallows the rest of the line rather than guessing at a prompt.")
    func anUnclosedQuoteIsConservative() {
        #expect(ShellPrompt.input(in: "echo 'unclosed % git status") == "echo 'unclosed % git status")
    }

    @Test("Only the terminator and the space after it go, not what the user indented.")
    func onlyThePromptIsRemoved() {
        #expect(ShellPrompt.input(in: "user@host:~/dir$ git  log --oneline") == "git  log --oneline")
    }
}

@Suite("Shell prompt credential detection")
struct ShellPromptCredentialTests {
    @Test("credential prompt detection delegates to the shared recognizer")
    func credentialPromptUsesSharedRecognizer() {
        #expect(ShellPrompt.isCredentialPrompt(in: "Authentication code: hidden"))
        #expect(ShellPrompt.isCredentialPrompt(in: "Enter same passphrase again: hidden"))
        #expect(ShellPrompt.isCredentialPrompt(in: "Token:"))
        #expect(!ShellPrompt.isCredentialPrompt(in: "token: abc"))
        #expect(ShellPrompt.isCredentialPrompt(in: "API token:"))
        #expect(ShellPrompt.isCredentialPrompt(in: "Password (again):"))
        #expect(!ShellPrompt.isCredentialPrompt(in: "echo 'Verification code: value'"))
    }
}
