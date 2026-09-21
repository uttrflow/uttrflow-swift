import Testing

@testable import UttrflowPredict

/// The words of each simple command in a line, as plain text.
private func words(_ line: String) -> [[String]]? {
    ShellWords.commands(in: line, home: "/home/someone")?.map { $0.words.map(\.text) }
}

@Suite("Reading a command line as the shell reads it")
struct ShellWordsTests {
    @Test("Quotes and escapes are undone, and one quoted path is one word.")
    func quoting() {
        #expect(words(#"cd "My Folder""#) == [["cd", "My Folder"]])
        #expect(words("cd 'My Folder'") == [["cd", "My Folder"]])
        #expect(words(#"cd My\ Folder"#) == [["cd", "My Folder"]])
        #expect(words(#"echo "a \"b\" \$c \\ \d""#) == [["echo", #"a "b" $c \ \d"#]])
        #expect(words("echo 'it''s'") == [["echo", "its"]])
        #expect(words("cat a\\\nb") == [["cat", "ab"]])
        #expect(words("echo \"a\\\nb\"") == [["echo", "ab"]])
    }

    @Test("Home is expanded from a bare tilde and from HOME; anything else the shell would expand is marked.")
    func expansion() throws {
        #expect(words("cd ~/src") == [["cd", "/home/someone/src"]])
        #expect(words("cd ~") == [["cd", "/home/someone"]])
        #expect(words("cd $HOME/src \"${HOME}\"") == [["cd", "/home/someone/src", "/home/someone"]])
        #expect(words("echo a~b") == [["echo", "a~b"]])
        let marked = try #require(
            ShellWords.commands(in: "cat ~other/x $PATH $1 *.md x? {a,b} \"$X\" $", home: "/h"))
        #expect(
            marked[0].words.map(\.isUnresolved) == [false, true, true, true, true, true, true, true, false])
        #expect(marked[0].words.last?.text == "$")
        let brackets = try #require(ShellWords.commands(in: "[ -f x ] && [[ -d y ]]", home: "/h"))
        #expect(brackets.flatMap(\.words).allSatisfy { !$0.isUnresolved })
        #expect(words("echo \"$\" $ \"x\"") == [["echo", "$", "$", "x"]])
    }

    @Test("Operators end a simple command, each with what ended it.")
    func separators() throws {
        let commands = try #require(ShellWords.commands(in: "a && b || c | d ; e & f\ng |& h", home: "/h"))
        #expect(
            commands.map(\.separator) == [.and, .or, .pipe, .sequence, .background, .sequence, .pipe, .end])
        #expect(words("a;;b") == [["a"], ["b"]])
        #expect(words("ls # cd nowhere") == [["ls"]])
        #expect(words("") == [])
    }

    @Test("Redirections are not arguments, and the files read with < are kept.")
    func redirections() throws {
        let command = try #require(
            ShellWords.commands(in: "sort < in.txt > out.txt 2>&1 >> log &> all 2>/dev/null", home: "/h"))
        #expect(command.map { $0.words.map(\.text) } == [["sort"]])
        #expect(command[0].inputs.map(\.text) == ["in.txt"])
        #expect(words("echo x >| file <> both 1>&-") == [["echo", "x"]])
        #expect(words("echo \"2\">file") == [["echo", "2"]])
        #expect(words("ls a2>err") == [["ls", "a2"]])
    }

    @Test(
        "A line only running something could settle is not read at all.",
        arguments: [
            "(cd x)", "ls $(pwd)", "ls `pwd`", "echo \"`pwd`\"", "cat <<EOF", "cat <<<word", "diff <(a) <(b)",
            "tee >(cat)", "{ ls; }", "echo 'open", "echo \"open", "echo \\", "echo \"\\", "&& ls", "| ls",
            "cat <",
            "cat < < x", "ls >", "echo $'x'", "echo ${X", "echo \"$(date)\"", "a ; && b",
        ])
    func refuses(_ line: String) {
        #expect(ShellWords.commands(in: line, home: "/h") == nil, "\(line)")
    }
}
