import Foundation
import Testing

@testable import UttrflowPredict

/// A project on a laid-out disk: a Swift service with a repository, a home and a handful of programs.
private func project() -> FakeDisk {
    FakeDisk(
        home: "/Users/someone", searchPaths: ["/usr/bin", "/opt/homebrew/bin"],
        directories: [
            "/Users/someone/api/Sources/Login", "/Users/someone/api/docs", "/Users/someone/api/My Folder",
            "/Users/someone/api/.git/refs/heads/fix", "/Users/someone/api/.git/refs/remotes/origin",
            "/Users/someone/web/src", "/Volumes/Backup",
        ],
        files: [
            "/Users/someone/api/Package.swift", "/Users/someone/api/docs/deploy.md",
            "/Users/someone/api/.env",
            "/Users/someone/api/Sources/Login/Session.swift", "/Users/someone/.zshrc",
            "/Users/someone/api/.git/refs/heads/main", "/Users/someone/api/.git/refs/heads/fix/login",
            "/Users/someone/api/.git/refs/tags/v1.0", "/Users/someone/api/.git/refs/remotes/origin/release",
            "/Users/someone/api/My Folder/notes.txt",
        ],
        executables: [
            "/usr/bin/git", "/usr/bin/cat", "/usr/bin/ls", "/usr/bin/vim", "/usr/bin/grep", "/usr/bin/cp",
            "/usr/bin/mv", "/usr/bin/python3", "/usr/bin/chmod", "/usr/bin/sudo", "/usr/bin/env",
            "/usr/bin/open",
            "/opt/homebrew/bin/rg", "/usr/bin/head", "/usr/bin/make", "/Users/someone/api/run.sh",
            "/usr/bin/code",
        ],
        texts: [
            "/Users/someone/api/.git/packed-refs":
                "# pack-refs with: peeled fully-peeled sorted\nabc123 refs/heads/packed\n^def456\nabc124 refs/remotes/upstream/fix/packed-remote\n"
        ])
}

/// The check over the project disk.
private let check = TerminalLineCheck(files: project())

/// The directory most lines are judged from.
private let api = "/Users/someone/api"

@Suite("Checking a terminal line against the disk")
struct TerminalLineCheckTests {
    @Test(
        "Lines whose every command, path and branch exists are allowed.",
        arguments: [
            "cd Sources/Login", "cd ..", "cd ../web/src", "cd", "cd ~", "cd -", "pushd +1", "popd",
            "cd -P docs",
            "cd /Users/someone/web", "cd ~/web/src", "cd $HOME/web", "cd ${HOME}/web", #"cd "My Folder""#,
            #"cd My\ Folder"#, "cd 'My Folder' && cat notes.txt", "cat Package.swift", "cat -",
            "head -n 5 .env",
            "vim +10 Package.swift", "vim docs/", "ls", "ls -la docs Sources",
            "cp Package.swift backup.swift",
            "mv .env docs/", "chmod 600 .env", "python3 Package.swift", "python3 -m http.server",
            "grep -rn import Sources", "rg -e import docs", "grep import", "./run.sh", "~/api/run.sh",
            "sudo -u root cat .env", "env FOO=1 cat .env", "FOO=1 make build", "echo $PATH", "cat < .env",
            "ls 2>/dev/null", "ls &> out.txt", "ls > out.txt 2>&1", "open https://example.com",
            "open -a Safari",
            "code .", "git status", "git checkout main", "git checkout fix/login", "git checkout v1.0",
            "git checkout origin/release", "git checkout release", "git checkout -", "git checkout HEAD~2",
            "git checkout main~1", "git checkout packed", "git checkout -b new-branch",
            "git checkout -b new main",
            "git checkout -- Package.swift", "git checkout main Package.swift", "git checkout Package.swift",
            "git switch main", "git switch release", "git switch -", "git switch -c topic",
            "git switch -c topic origin/release", "git switch --detach v1.0", "git switch fix/packed-remote",
            "git add .", "git add -A", "git add Sources/Login/Session.swift", "git restore --staged .env",
            "git mv .env .env.example", "git -c core.pager=cat checkout main", "ls | grep swift",
            "ls; cat .env", "ls & cat .env", "[ -f .env ] && cat .env", "cat .env # a comment",
            "true || false",
            "ls docs; cd Sources && ls",
        ])
    func allowsWhatExists(_ line: String) {
        #expect(check.allows(line, in: api), "\(line) names only what exists")
    }

    @Test(
        "Lines naming anything that is not here are refused.",
        arguments: [
            "cd Nowhere", "cd Package.swift", "cd docs extra", "cat docs", "cat missing.md",
            "cat docs/missing.md",
            "cat ~missing/file", "vim .env.vim", "ls Nowhere", "cp missing.txt docs/", "mv gone",
            "chmod 600 gone",
            "python3 missing.py", "grep -rn import Nowhere", "rg -e import Nowhere", "./missing.sh",
            "./Package.swift", "docs", "yarn build", "go test ./...", "cargo --help", "npm run dev",
            "cat *.swift", "cat $FILE", "cat ${FILE}", "cat \"$FILE\"", "cat $1", "ls $(pwd)", "ls `pwd`",
            "(cd docs && ls)", "{ ls; }", "cat <<EOF", "cat <(ls)", "cat 'unterminated", "cat \"unterminated",
            "cat trailing\\", "&& ls", "cat <", "ls >", "cat < missing", "cd docs || cat deploy.md",
            "cd docs | cat deploy.md", "cd docs & cat deploy.md", "cd - && cat deploy.md",
            "git checkout gone",
            "git checkout -b new gone", "git checkout gone Package.swift", "git checkout $BRANCH",
            "git checkout -- missing", "git checkout 0123abc", "git checkout - main", "git switch gone",
            "git switch v1.0", "git switch -c topic gone", "git switch main extra", "git switch $BRANCH",
            "git add missing.swift", "git mv gone somewhere", "git -C elsewhere checkout main",
            "git --git-dir=elsewhere checkout main", "git checkout main..release", "git checkout 'bad name'",
            "cat Package.swift/", "vim Package.swift/", "cat $'quoted'", "cat ${HOME", "echo `date`",
        ])
    func refusesWhatIsMissing(_ line: String) {
        #expect(!check.allows(line, in: api), "\(line) names something that is not here")
    }

    @Test("Without a directory that exists, relative paths are refused and absolute ones are still checked.")
    func unknownDirectory() {
        for scope in [nil, "", "api", "~/api (-zsh)", "/Users/someone/nowhere"] {
            #expect(!check.allows("cat Package.swift", in: scope))
            #expect(check.allows("cat /Users/someone/api/Package.swift", in: scope))
            #expect(check.allows("cat ~/api/Package.swift", in: scope))
            #expect(!check.allows("git checkout main", in: scope))
        }
        #expect(check.allows("cat Package.swift", in: "~/api"))
    }

    @Test("A command no builtin, alias or search path names is refused, and an alias is taken at its word.")
    func commands() {
        #expect(!check.allows("ll docs", in: api))
        #expect(check.allows("ll docs", in: api, aliases: ["ll"]))
        #expect(!check.allows("cat Nowhere", in: api, aliases: ["cat"]))
        #expect(!check.allows("$EDITOR .env", in: api))
        #expect(check.allows("rg import", in: api))
    }

    @Test("A disk that does not answer is never taken as saying yes.")
    func unknownIsRefused() {
        let disk = FakeDisk(
            directories: ["/work"], executables: ["/usr/bin/cat", "/usr/bin/git"],
            unknown: ["/work/slow.txt", "/work/.git"])
        let check = TerminalLineCheck(files: disk)
        #expect(!check.allows("cat slow.txt", in: "/work"))
        #expect(!check.allows("git checkout main", in: "/work"))
    }

    @Test(
        "Verification runs nothing: a line whose program is not here is refused before any program's verbs are asked for."
    )
    func runsNothing() async {
        let disk = project()
        let reader = KindRecorder()
        let verifier = Verifier(
            index: EnvironmentIndex(reader: reader), budgetInMilliseconds: 200, files: disk)
        let terminal = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: api)
        let lines = [
            "yarn build", "go test ./...", "npm run dev", "cargo --help", "git checkout gone", "docker ps",
        ]
        let candidates = lines.map { Candidate(text: $0, source: .personal) }
        #expect(await verifier.verified(candidates, in: terminal, typed: "", now: moment).isEmpty)
        #expect(await verifier.standing(lines, after: "", in: terminal, now: moment).isEmpty)
        // Only the shell's aliases are asked for, and they are read from its configuration as text.
        #expect(await reader.asked.allSatisfy { $0 == .alias })
        // The disk is the rest of what verification touched, and it offers nothing but a stat, a read and a listing.
        #expect(disk.operations.contains(.stat("/opt/homebrew/bin/yarn")))
    }

    @Test("A worktree's refs are read from the repository it belongs to, and a reftable is not read at all.")
    func worktrees() {
        let disk = FakeDisk(
            directories: [
                "/repo/.git/refs/heads", "/repo/.git/worktrees/wt", "/wt/src", "/table/.git/reftable",
            ],
            files: ["/repo/.git/refs/heads/main"], executables: ["/usr/bin/git"],
            texts: [
                "/wt/.git": "gitdir: /repo/.git/worktrees/wt\n",
                "/repo/.git/worktrees/wt/commondir": "../..\n",
                "/broken/.git": "nothing here\n",
            ])
        let check = TerminalLineCheck(files: disk)
        #expect(check.allows("git checkout main", in: "/wt/src"))
        #expect(!check.allows("git checkout main", in: "/table"))
        #expect(!check.allows("git checkout main", in: "/broken"))
        #expect(!check.allows("git checkout main", in: "/"))
    }

    @Test("A packed-refs too large to read whole vouches for nothing.")
    func largePackedRefs() {
        let huge = String(repeating: "abc refs/heads/other\n", count: GitRepository.packedRefsLimit / 20 + 1)
        let disk = FakeDisk(
            directories: ["/repo/.git/refs/heads"], executables: ["/usr/bin/git"],
            texts: ["/repo/.git/packed-refs": huge + "abc refs/heads/main\n"])
        #expect(!TerminalLineCheck(files: disk).allows("git checkout main", in: "/repo"))
    }

    @Test("A ref's name cannot climb out of the refs directory or carry what git forbids.")
    func refNames() {
        for name in ["main", "fix/login", "v1.0"] { #expect(GitRepository.isRefName(name)) }
        for name in ["", "/main", "main/", "a..b", "a//b", "x.lock", "a b", "a:b", "a@{1}", "a\u{1}b"] {
            #expect(!GitRepository.isRefName(name), "\(name)")
        }
    }

    @Test("The refs a repository holds are listed by their short names, loose and packed.")
    func listsRefs() throws {
        let disk = project()
        let repository = try #require(GitRepository.holding("\(api)/Sources", files: disk))
        #expect(
            repository.refNames(limit: 50) == [
                "fix/login", "main", "origin/release", "packed", "upstream/fix/packed-remote", "v1.0",
            ])
        #expect(repository.refNames(limit: 2).count == 2)
    }

    @Test("A path is folded the way cd folds it, never above root.")
    func paths() {
        #expect(TerminalPath.normalized("/a/./b/../c//") == "/a/c")
        #expect(TerminalPath.normalized("/../..") == "/")
        #expect(TerminalPath.resolved("../x", from: "/a/b") == "/a/x")
        #expect(TerminalPath.resolved("/x", from: "/a") == "/x")
        #expect(TerminalPath.joined("/", "a") == "/a")
        #expect(TerminalPath.parent(of: "/") == "/")
        #expect(TerminalPath.lastName(of: "/usr/bin/git") == "git")
        #expect(TerminalPath.lastName(of: "/") == "/")
    }
}
