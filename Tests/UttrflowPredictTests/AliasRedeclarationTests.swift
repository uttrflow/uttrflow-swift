import Testing
import UttrflowTestSupport

@testable import UttrflowPredict

struct AliasRedeclarationTests {
    @Test(arguments: ["git status | cat", "git status; cat", "git status > output", "$(opaque)", "git *", ""])
    func unsupportedLastBindingInvalidatesEarlierBody(_ body: String) {
        let configuration = "alias git='git status'\nalias git='\(body)'\n"
        #expect(ShellAliases.expansions(in: configuration).isEmpty)
        #expect(ShellAliases.names(in: configuration) == ["git", "git"])
    }

    @Test func supportedLastBindingRestoresExpansion() {
        let configuration = """
            alias git='git status'
            alias git='$(opaque)'
            alias git='git checkout'
            """
        #expect(ShellAliases.expansions(in: configuration) == ["git": ["git", "checkout"]])
    }

    @Test func unsupportedRedeclarationPreservesUnrelatedBody() {
        let configuration = """
            alias gco='git checkout'
            alias other='git status'
            alias other='git status | cat'
            """
        #expect(ShellAliases.expansions(in: configuration) == ["gco": ["git", "checkout"]])
        #expect(ShellAliases.names(in: configuration) == ["gco", "other", "other"])
    }

    @Test func nondeclarationDoesNotInvalidateBody() {
        let configuration = "alias gco='git checkout'\n# alias gco='$(opaque)'\nalias -p\n"
        #expect(ShellAliases.expansions(in: configuration) == ["gco": ["git", "checkout"]])
    }

    @Test func supportedBindingReplacesInitiallyUnsupportedBody() {
        let configuration = "alias gco='$(opaque)'\nalias gco='git checkout'\n"
        #expect(ShellAliases.expansions(in: configuration) == ["gco": ["git", "checkout"]])
    }

    @Test func configuredFileOrderInvalidatesEarlierExpansion() async {
        let files = FakeDisk(
            home: "/fixture",
            texts: [
                "/fixture/.zshrc": "alias gco='git checkout'\nalias ll='ls -la'\n",
                "/fixture/.aliases": "alias gco='git status | cat'\n",
            ])
        let reader = SystemEnvironmentReader(
            launcher: RedeclarationLauncher(), programDirectories: [], files: files)
        #expect(await reader.aliasExpansions() == ["ll": ["ls", "-la"]])
    }
}

private struct RedeclarationLauncher: ProgramLaunching {
    func output(of launch: ProgramLaunch) async -> String? { nil }
}
