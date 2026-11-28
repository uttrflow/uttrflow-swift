// Tests where programs are looked for and how each is asked to list its verbs.
import Testing

@testable import UttrflowPredict

@Suite("Environment search rules")
struct EnvironmentSearchRulesTests {
    @Test("a program that keeps a listing command is asked with it, and every other with help")
    func listingArguments() {
        #expect(EnvironmentSearchRules.listingArguments(for: "cargo") == ["--list"])
        #expect(EnvironmentSearchRules.listingArguments(for: "brew") == ["commands", "--quiet"])
        #expect(EnvironmentSearchRules.listingArguments(for: "npm") == ["help"])
        #expect(EnvironmentSearchRules.listingArguments(for: "make") == ["--help"])
        #expect(EnvironmentSearchRules.listingArguments(for: "") == ["--help"])
    }

    @Test("the launch PATH comes first, then the extra directories")
    func launchedThenExtra() {
        #expect(
            EnvironmentSearchRules.searchPaths(path: "/usr/bin:/bin")
                == ["/usr/bin", "/bin", "/opt/homebrew/bin", "/usr/local/bin"])
    }

    @Test("a missing PATH leaves only the extra directories")
    func noPath() {
        #expect(EnvironmentSearchRules.searchPaths(path: nil) == EnvironmentSearchRules.extraSearchPaths)
        #expect(EnvironmentSearchRules.searchPaths(path: "") == EnvironmentSearchRules.extraSearchPaths)
    }

    @Test("duplicates and empty components go, and the first place of each directory is kept")
    func duplicatesAndEmpties() {
        #expect(
            EnvironmentSearchRules.searchPaths(path: "/bin::/usr/bin:/bin:")
                == ["/bin", "/usr/bin", "/opt/homebrew/bin", "/usr/local/bin"])
    }

    @Test("an entry that is also an extra directory stays where PATH put it")
    func extraAlreadyOnPath() {
        #expect(
            EnvironmentSearchRules.searchPaths(path: "/usr/local/bin:/usr/bin")
                == ["/usr/local/bin", "/usr/bin", "/opt/homebrew/bin"])
    }
}
