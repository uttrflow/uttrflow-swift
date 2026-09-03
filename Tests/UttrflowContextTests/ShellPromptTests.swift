import Testing

@testable import UttrflowContext

@Suite("What a terminal line holds once the shell prompt is taken off it")
struct ShellPromptTests {
    @Test("A default zsh prompt is taken off, hostname and all.")
    func zshDefaultPrompt() {
        #expect(
            ShellPrompt.input(in: "naveenbhatt@Naveens-MacBook-Pro-2 experiments % git status")
                == "git status")
    }

    @Test("A virtualenv in front of the prompt is part of the prompt.")
    func virtualenvPrefix() {
        #expect(
            ShellPrompt.input(
                in: "(experiments) naveenbhatt@Naveens-MacBook-Pro-2 experiments % sudo") == "sudo")
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

    @Test("A root prompt is a hash with nothing in front of it.")
    func rootPrompt() {
        #expect(ShellPrompt.input(in: "# apt update") == "apt update")
        #expect(ShellPrompt.input(in: "root@host:~# apt update") == "apt update")
    }

    @Test("A python prompt is a run of chevrons.")
    func pythonPrompt() {
        #expect(ShellPrompt.input(in: ">>> import os") == "import os")
        #expect(ShellPrompt.input(in: "> require('os')") == "require('os')")
    }

    @Test("A database prompt ends at the hash or the chevron its equals sign leads to.")
    func databasePrompt() {
        #expect(ShellPrompt.input(in: "uttrflow=# select") == "select")
        #expect(ShellPrompt.input(in: "uttrflow=> select") == "select")
    }

    @Test("A starship chevron ends a prompt too.")
    func chevronPrompt() {
        #expect(ShellPrompt.input(in: "~/dir on main ❯ ls") == "ls")
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
        #expect(ShellPrompt.input(in: "naveenbhatt@Naveens-MacBook-Pro-2 experiments % ").isEmpty)
        #expect(ShellPrompt.input(in: "naveenbhatt@Naveens-MacBook-Pro-2 experiments %").isEmpty)
        #expect(ShellPrompt.input(in: "user@host:~/dir$").isEmpty)
        #expect(ShellPrompt.input(in: ">>>").isEmpty)
    }

    @Test("A percentage inside a command is not a prompt, whether or not a prompt precedes it.")
    func aPercentageIsNotAPrompt() {
        #expect(ShellPrompt.input(in: #"echo "50% done""#) == #"echo "50% done""#)
        #expect(ShellPrompt.input(in: "echo 50% done") == "echo 50% done")
        #expect(
            ShellPrompt.input(in: #"naveenbhatt@host experiments % echo "50% done""#)
                == #"echo "50% done""#)
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
    }

    @Test("A trailing comment is not a root prompt.")
    func aCommentIsNotAPrompt() {
        #expect(ShellPrompt.input(in: "echo hi # note") == "echo hi # note")
        #expect(ShellPrompt.input(in: "user@host:~/dir$ echo hi # note") == "echo hi # note")
    }

    @Test("An escaped quote does not open one, so a later prompt character is still seen.")
    func anEscapedQuoteOpensNothing() {
        #expect(ShellPrompt.input(in: #"user\@host:~/dir$ ls"#) == "ls")
        #expect(ShellPrompt.input(in: #"echo \" 50% done"#) == #"echo \" 50% done"#)
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
