import Testing

@testable import UttrflowContext

@Suite("Which program owns a terminal line, read from the prompt text only")
struct LineOwnerTests {
    @Test(
        "Interpreter prompts name their language.",
        arguments: [
            ("inventory=# select * from parts;", ReplLanguage.sql),
            ("inventory=> select 1", .sql),
            ("inventory=*# rollback;", .sql),
            ("inventory-# from parts", .sql),
            ("inventory(# values (1)", .sql),
            ("mysql> show tables;", .sql),
            ("mariadb> show tables;", .sql),
            ("MariaDB [shop]> select 1;", .sql),
            ("sqlite> .tables", .sql),
            (">>> print(1)", .python),
            (">>>", .python),
            ("In [12]: import os", .python),
            ("(Pdb) next", .python),
            ("irb(main):001> puts 1", .ruby),
            ("irb(main):002:1> puts 2", .ruby),
        ])
    func interpreterPrompts(line: String, language: ReplLanguage) {
        #expect(ShellPrompt.lineOwner(of: line) == .repl(language))
    }

    @Test(
        "Shell prompts name their family where the shape does.",
        arguments: [
            ("user@host experiments % git status", LineOwner.shell(.zsh)),
            ("➜  uttrflow git:(main) ✗ git status", .shell(.zsh)),
            ("user@host:~/dir$ git status", .shell(.posix)),
            ("root@host:/etc# ls", .shell(.posix)),
            ("PS C:\\Users\\sample> Get-Date", .shell(.powerShell)),
            ("~/project ❯ ls", .shell(.unspecified)),
        ])
    func shellPrompts(line: String, owner: LineOwner) {
        #expect(ShellPrompt.lineOwner(of: line) == owner)
    }

    @Test(
        "Look-alikes and unrecognised text own nothing.",
        arguments: [
            "",
            "select * from parts;",
            "echo >>> notes",
            ">>>text",
            "mysql>show tables",
            "inventory=#select",
            "In [x]: import os",
            "In [3] import os",
            "irb(main):abc> puts",
            "MariaDB [] > select",
            "The price is 5 dollars",
        ])
    func lookAlikes(line: String) {
        #expect(ShellPrompt.lineOwner(of: line) == .unknown)
    }

    @Test("A python prompt typed after a shell prompt is the shell's command, not a REPL.")
    func promptAfterShellPrompt() {
        #expect(ShellPrompt.lineOwner(of: "user@host:~$ echo '>>> '") == .shell(.posix))
    }

    @Test("A prompt-shaped line inside a heredoc body owns nothing.")
    func heredocBody() {
        let screen = "user@host:~$ cat <<EOF\ninventory=# select 1;"
        #expect(ShellPrompt.lineOwner(in: screen, before: screen.endIndex) == .unknown)
    }

    @Test("The line holding the caret is the one judged.")
    func lastLineOfScreen() {
        let screen = "user@host:~$ psql\ninventory=# select 1;"
        #expect(ShellPrompt.lineOwner(in: screen, before: screen.endIndex) == .repl(.sql))
        #expect(ShellPrompt.lineOwner(in: "", before: "".endIndex) == .unknown)
    }
}
