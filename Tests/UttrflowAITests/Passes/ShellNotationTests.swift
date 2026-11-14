import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken command line is written as the command line")
struct ShellNotationTests {
    private func written(_ spoken: String) -> String {
        let app = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test(
        "writes variables, substitutions, quotes, redirections and chaining as said",
        arguments: [
            ("echo dollar home", "echo $home"),
            ("cd dollar home", "cd $home"),
            ("echo dollar home slash bin", "echo $home/bin"),
            ("echo dollar open paren date close paren", "echo $(date)"),
            ("echo dollar open brace home close brace", "echo ${home}"),
            ("echo dollar question mark", "echo $?"),
            ("echo single quote hi there single quote", "echo 'hi there'"),
            ("git commit dash m single quote fix bug single quote", "git commit -m 'fix bug'"),
            ("git commit dash m quote fix bug quote", "git commit -m \"fix bug\""),
            ("grep quote hello world quote notes dot txt", "grep \"hello world\" notes.txt"),
            ("make build ampersand ampersand make test", "make build && make test"),
            ("ls dash la ampersand ampersand pwd", "ls -la && pwd"),
            ("echo hello greater than out dot txt", "echo hello > out.txt"),
            ("echo backslash n", "echo \\n"),
            ("cd tilde slash projects", "cd ~/projects"),
            ("ls dash la tilde", "ls -la ~"),
            ("ls star dot txt", "ls *.txt"),
            ("rm dash rf build semicolon ls", "rm -rf build; ls"),
            ("ls semicolon pwd", "ls; pwd"),
            ("cat file dot txt pipe wc dash l", "cat file.txt | wc -l"),
            ("cd dot dot slash src", "cd ../src"),
            ("chmod plus x run dot sh", "chmod +x run.sh"),
            ("tail dash f var slash log slash syslog", "tail -f var/log/syslog"),
        ])
    func writesCommand(spoken: String, expected: String) {
        #expect(written(spoken) == expected)
    }

    @Test(
        "leaves a sentence with a word of the same name as a symbol as the words",
        arguments: [
            ("five dollar bill", "5 dollar bill"),
            ("i paid ten dollar for lunch", "i paid 10 dollar for lunch"),
            ("it costs five dollar", "it costs 5 dollar"),
            ("the single quote key", "the single quote key"),
            ("backslash is a slash", "backslash is a slash"),
            ("tom and jerry went home", "tom and jerry went home"),
            ("we need a ten dollar budget", "we need a 10 dollar budget"),
            ("two dollar coins", "2 dollar coins"),
            ("the dollar rate", "the dollar rate"),
            ("use the backslash key to escape", "use the backslash key to escape"),
            ("a dollar for the meter", "a dollar for the meter"),
            ("twenty dollar notes", "20 dollar notes"),
        ])
    func keepsProse(spoken: String, expected: String) {
        #expect(written(spoken) == expected)
    }

    @Test("keeps a digit numeral before a leading symbol's name as words, and a bracket on the command")
    func digitsAndBrackets() {
        #expect(written("echo 5 dollar bill") == "echo 5 dollar bill")
        #expect(written("echo open paren dollar home close paren") == "echo ($home)")
    }
}
