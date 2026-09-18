import Foundation
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

    @Test(
        "A justfile's recipes are its public recipe heads and aliases, without settings, variables or modules."
    )
    func justfileRecipes() {
        let justfile = """
            set shell := ["zsh", "-cu"]
            export PATH := "bin:" + env_var('PATH')
            version := "1.0"
            import 'common.just'
            mod deploy

            # Runs every check.
            verify: lint test
            \tswift test

            @lint:
            \tswiftlint

            test filter="": build
            \tswift test --filter {{filter}}

            serve addr="127.0.0.1:8080" *args:
            \t./serve {{addr}} {{args}}

            [private]
            helper:
            \techo hidden

            _setup:
            \techo hidden too

            [group('release')]
            build-app:
            \techo building

            alias b := build-app

            [group('private')]
            docs:
            \techo public

            [no-cd, private]
            clean:
            \techo hidden as well
            """
        #expect(
            JustfileRecipes.names(in: justfile) == [
                "verify", "lint", "test", "serve", "build-app", "b", "docs",
            ])
        #expect(JustfileRecipes.names(in: "") == [])
    }

    /// `just` and `make` each read their own file, so a project with both offers each only its own verbs.
    @Test("just reads the justfile and make the Makefile, in a project with one or both")
    func justAndMakeReadTheirOwnFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "verbs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SystemEnvironmentReader()

        try Data("verify-just:\n\techo just\n".utf8).write(to: directory.appending(path: "justfile"))
        #expect(await reader.values(of: .subcommand(of: "just"), in: directory.path) == ["verify-just"])
        #expect(await reader.values(of: .subcommand(of: "make"), in: directory.path) == nil)

        try Data("verify-make:\n\techo make\n".utf8).write(to: directory.appending(path: "Makefile"))
        #expect(await reader.values(of: .subcommand(of: "just"), in: directory.path) == ["verify-just"])
        #expect(await reader.values(of: .subcommand(of: "make"), in: directory.path) == ["verify-make"])
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
