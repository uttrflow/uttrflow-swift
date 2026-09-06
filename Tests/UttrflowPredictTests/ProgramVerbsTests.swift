import Testing

@testable import UttrflowPredict

@Suite("Reading the verbs a program takes")
struct ProgramVerbsTests {
    @Test("A Makefile's targets are its rule heads, without variables, recipes, special targets or patterns.")
    func makefileTargets() {
        let makefile = """
            SWIFT := xcrun swift
            .PHONY: verify build
            verify: lint test
            \t$(SWIFT) test
            build test:
            \t@echo building
            %.o: %.c
            $(TARGET): build
            # release: not yet
            """
        #expect(MakefileTargets.names(in: makefile) == ["verify", "build", "test"])
    }

    @Test("A manifest's scripts are the keys of its scripts object, whatever their commands hold.")
    func packageScripts() {
        let manifest = """
            {
              "name": "app",
              "scripts": {
                "dev": "vite",
                "build": "tsc && vite build",
                "test:unit": "vitest run --reporter=\\"dot, verbose\\"",
                "lint": "eslint ."
              },
              "dependencies": { "vite": "^5" }
            }
            """
        #expect(PackageScripts.names(in: manifest) == ["build", "dev", "lint", "test:unit"])
        #expect(PackageScripts.names(in: "{ \"name\": \"app\" }") == [])
        #expect(PackageScripts.names(in: "scripts: dev") == nil)
    }

    @Test(
        "A help page's commands are its indented names, set off from their descriptions or listed with commas."
    )
    func helpCommands() {
        let docker = """
            Usage:  docker [OPTIONS] COMMAND

            Common Commands:
              run         Create and run a new container from an image
              exec        Execute a command in a running container
              ps          List containers

            Global Options:
                  --config string      Location of client config files
              -D, --debug              Enable debug mode
            """
        #expect(HelpCommands.names(in: docker) == ["run", "exec", "ps"])
        let gh =
            "CORE COMMANDS\n  auth:          Authenticate gh and git with GitHub\n  pr:            Manage pull requests\n"
        #expect(HelpCommands.names(in: gh) == ["auth", "pr"])
        let cargo =
            "Installed Commands:\n    add                  Add dependencies\n    audit\n    b                    alias: build\n"
        #expect(HelpCommands.names(in: cargo) == ["add", "audit", "b"])
        let npm = "All commands:\n\n    access, adduser, audit, bugs,\n    completion, config\n"
        #expect(
            HelpCommands.names(in: npm) == ["access", "adduser", "audit", "bugs", "completion", "config"])
        #expect(HelpCommands.names(in: "--cache\ncommands\ninstall\n") == ["commands", "install"])
        #expect(HelpCommands.names(in: "Usage: swift [options] file\n  Compiles the file given.\n").isEmpty)
    }
}
