import Foundation
import Synchronization
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

/// A fork with two remotes: `shared` on both, `solo` on one alone though both loose and packed, `split` loose on one and packed on the other.
private func fork() -> FakeDisk {
    FakeDisk(
        home: "/Users/someone", searchPaths: ["/usr/bin"],
        directories: [
            "/Users/someone/fork/.git/refs/heads", "/Users/someone/fork/.git/refs/remotes/origin",
            "/Users/someone/fork/.git/refs/remotes/upstream",
        ],
        files: [
            "/Users/someone/fork/.git/refs/heads/main", "/Users/someone/fork/.git/refs/remotes/origin/shared",
            "/Users/someone/fork/.git/refs/remotes/upstream/shared",
            "/Users/someone/fork/.git/refs/remotes/origin/solo",
            "/Users/someone/fork/.git/refs/remotes/origin/split",
        ],
        executables: ["/usr/bin/git"],
        texts: [
            "/Users/someone/fork/.git/packed-refs":
                "abc123 refs/remotes/origin/solo\nabc124 refs/remotes/upstream/split\nabc125 refs/remotes/upstream/packed-only\n"
        ])
}

/// A packed-refs disk that records reads and lets the next lookup see a replacement file.
private final class MutablePackedRefsDisk: FileSystemProbing {
    private struct State: Sendable {
        var text: String
        var reads = 0
    }

    private let disk: FakeDisk
    private let path = "/Users/someone/repo/.git/packed-refs"
    private let state: Mutex<State>

    init(text: String) {
        disk = FakeDisk(directories: ["/Users/someone/repo/.git/refs/remotes/origin"])
        state = Mutex(State(text: text))
    }

    var environment: FileSystemEnvironment { disk.environment }
    var packedRefsReads: Int { state.withLock { $0.reads } }

    func replacePackedRefs(with text: String) {
        state.withLock { $0.text = text }
    }

    func kind(atPath path: String) -> PathKind {
        path == self.path ? .file(executable: false) : disk.kind(atPath: path)
    }

    func contents(ofFile path: String, limit: Int) -> String? {
        guard path == self.path else { return disk.contents(ofFile: path, limit: limit) }
        return state.withLock {
            $0.reads += 1
            return $0.text.utf8.count <= limit ? $0.text : nil
        }
    }

    func names(inDirectory path: String, limit: Int) -> [String]? {
        disk.names(inDirectory: path, limit: limit)
    }

    func visitNames(inDirectory path: String, _ visit: (String) -> Bool) -> Bool? {
        disk.visitNames(inDirectory: path, visit)
    }
}

/// A project with one script per interpreter and each interpreter on the search path.
private let scripts = TerminalLineCheck(
    files: FakeDisk(
        home: "/Users/someone", searchPaths: ["/usr/bin"],
        directories: ["/Users/someone/tools"],
        files: [
            "/Users/someone/tools/present.py", "/Users/someone/tools/app.js", "/Users/someone/tools/run.sh",
            "/Users/someone/tools/task.rb", "/Users/someone/tools/fix.pl", "/Users/someone/tools/notes.txt",
        ],
        executables: [
            "/usr/bin/python3", "/usr/bin/node", "/usr/bin/bash", "/usr/bin/ruby", "/usr/bin/perl",
            "/usr/bin/php",
        ]))

@Suite("Checking the script an interpreter runs")
struct InterpreterScriptTests {
    @Test(
        "A script named after the interpreter's flags must exist here.",
        arguments: [
            "python3 -u missing.py", "python3 -W ignore missing.py", "python3 -B -O missing.py",
            "node --inspect gone.js", "node -r dotenv/config gone.js", "bash -x nothere.sh",
            "bash -o pipefail nothere.sh", "bash -l nothere.sh", "ruby -w old.rb", "ruby -I lib old.rb",
            "perl -w gone.pl", "perl -pie 's/a/b/' notes.txt", "php -f gone.php", "python3 -- missing.py",
        ])
    func missingScriptsAreRefused(_ line: String) {
        #expect(!scripts.allows(line, in: "/Users/someone/tools"), "\(line) names a missing script")
    }

    @Test(
        "A script that exists stands, and code given inline, as a module or on the standard input needs no file.",
        arguments: [
            "python3 -u present.py", "python3 -W ignore present.py", "python3 -m http.server",
            "python3 -c 'print(1)'",
            "python3 -Bc 'print(1)'", "python3", "python3 -", "node -e '1'", "node --eval=1", "node -p 1",
            "node --inspect app.js", "bash -x run.sh", "bash -lc 'ls'", "bash -s", "ruby -w task.rb",
            "ruby -e 'puts 1'", "perl -pi -e 's/a/b/' notes.txt", "perl -w fix.pl", "php -r 'echo 1;'",
        ])
    func presentAndInlineStand(_ line: String) {
        #expect(scripts.allows(line, in: "/Users/someone/tools"), "\(line) needs nothing missing")
    }

    @Test(
        "Scripts resolved outside the current directory do not have to exist here.",
        arguments: ["ruby -S rake", "perl -S prove", "node --run build"])
    func externalScriptsStand(_ line: String) {
        #expect(
            scripts.allows(line, in: "/Users/someone/tools"), "\(line) is resolved outside this directory")
    }
}

@Suite("Checking a git line in a repository with two remotes")
struct TwoRemoteCheckTests {
    @Test(
        "A branch only one remote has is checked out or switched to, however its refs are stored.",
        arguments: [
            "git switch solo", "git checkout solo", "git switch packed-only", "git checkout packed-only",
        ])
    func oneRemoteStands(_ line: String) {
        #expect(TerminalLineCheck(files: fork()).allows(line, in: "/Users/someone/fork"), "\(line)")
    }

    @Test(
        "A branch two remotes both have is refused, since git will not guess which one to track.",
        arguments: ["git switch shared", "git checkout shared", "git switch split", "git checkout split"])
    func twoRemotesAreAmbiguous(_ line: String) {
        #expect(!TerminalLineCheck(files: fork()).allows(line, in: "/Users/someone/fork"), "\(line)")
    }

    @Test("Each remote holding the branch is counted once, loose and packed together.")
    func remotesAreCountedOnce() throws {
        let repository = try #require(GitRepository.holding("/Users/someone/fork", files: fork()))
        #expect(repository.remotes(holdingBranch: "solo") == ["origin"])
        #expect(repository.remotes(holdingBranch: "split") == ["origin", "upstream"])
        #expect(repository.remotes(holdingBranch: "shared") == ["origin", "upstream"])
        #expect(repository.remotes(holdingBranch: "gone") == [])
    }
}

@Suite("Packed refs are memoized for one repository lookup")
struct PackedRefsCacheTests {
    @Test("Commit and remote checks read once, then the next lookup sees packed ref updates.")
    func oneReadPerLookupAndFreshNextLookup() throws {
        let disk = MutablePackedRefsDisk(
            text: "abc123 refs/heads/packed-only\nabc124 refs/remotes/origin/packed-only\n")
        let first = try #require(GitRepository.holding("/Users/someone/repo", files: disk))

        #expect(first.hasCommit(named: "packed-only"))
        #expect(first.hasRemoteBranch(named: "packed-only"))
        #expect(disk.packedRefsReads == 1)

        disk.replacePackedRefs(with: "abc124 refs/heads/new-after-update\n")
        let next = try #require(GitRepository.holding("/Users/someone/repo", files: disk))
        #expect(next.hasCommit(named: "new-after-update"))
        #expect(disk.packedRefsReads == 2)
    }
}

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
            "git checkout main~1", "git checkout HEAD@{1}", "git checkout @{-1}",
            "git checkout main^{commit}", "git checkout main^{tree}", "git checkout main@{0}^{commit}",
            "git checkout :/message", "git checkout packed", "git checkout -b new-branch",
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
            "git checkout HEAD@{bad}", "git checkout main^{unknown}", "git checkout main^{commit",
            "git checkout main@{}", "git checkout :/", "git checkout missing@{1}",
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

    @Test("A leading symbolic chmod mode is not mistaken for an option.")
    func chmodSymbolicModesCheckEveryPath() {
        #expect(!check.allows("chmod -x missing.sh", in: api))
        #expect(check.allows("chmod -x Package.swift", in: api))
        #expect(check.allows("chmod -x,g+w Package.swift", in: api))
        #expect(check.allows("chmod -R 755 docs", in: api))
        #expect(!check.allows("chmod -R 755 missing-dir", in: api))
    }

    @Test(
        "Search pattern files must exist before a terminal line is offered.",
        arguments: [
            "grep -f missing.patterns Package.swift", "rg --file missing.patterns Package.swift",
            "grep -fmissing.patterns Package.swift", "rg --file=missing.patterns Package.swift",
            "grep -f docs Package.swift", "rg --file=$PATTERNS Package.swift",
        ])
    func missingPatternFile(_ line: String) {
        #expect(!check.allows(line, in: api), "\(line) names a missing pattern file")
    }

    @Test(
        "A real pattern file passes, and regexp flags remain literal patterns.",
        arguments: [
            "grep -f .env Package.swift", "rg --file .env Package.swift",
            "grep -f.env Package.swift", "rg --file=.env Package.swift",
            "grep -e missing.patterns Package.swift", "rg --regexp=missing.patterns Package.swift",
            "grep -emissing.patterns Package.swift", "grep -f .env -e missing.patterns Package.swift",
            "grep -- -f Package.swift",
        ])
    func searchPatternValues(_ line: String) {
        #expect(check.allows(line, in: api), "\(line) can run with files present")
    }

    @Test(
        "The documented --regexp=PATTERN form checks file operands for grep and rg.",
        arguments: ["grep", "rg"])
    func regexpEqualsChecksFileOperands(_ command: String) {
        #expect(check.allows("\(command) --regexp=TODO Package.swift", in: api))
        #expect(!check.allows("\(command) --regexp=TODO missing.swift", in: api))
    }

    @Test("A pattern option without its value is refused.")
    func missingSearchOptionValue() {
        #expect(!check.allows("grep -f", in: api))
        #expect(!check.allows("rg --file", in: api))
        #expect(!check.allows("grep -e", in: api))
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
                "/repo/.git/worktrees/wt/gitdir": "/wt/.git\n",
                "/broken/.git": "nothing here\n",
            ])
        let check = TerminalLineCheck(files: disk)
        #expect(check.allows("git checkout main", in: "/wt/src"))
        #expect(!check.allows("git checkout main", in: "/table"))
        #expect(!check.allows("git checkout main", in: "/broken"))
        #expect(!check.allows("git checkout main", in: "/"))
    }

    @Test("Git metadata targets outside the repository and its linked worktree are refused.")
    func externalGitMetadataIsRefused() {
        let disk = FakeDisk(
            directories: ["/repo/.git", "/outside/.git/worktrees/wt", "/outside/.git/refs/heads"],
            files: ["/repo/.git/refs/heads/main"], executables: ["/usr/bin/git"],
            texts: [
                "/repo/.git/commondir": "/outside/.git\n",
                "/linked/.git": "gitdir: /outside/.git/worktrees/wt\n",
                "/outside/.git/worktrees/wt/commondir": "../..\n",
                "/outside/.git/worktrees/wt/gitdir": "/elsewhere/.git\n",
            ])
        let check = TerminalLineCheck(files: disk)
        #expect(!check.allows("git checkout main", in: "/repo"))
        #expect(!check.allows("git checkout main", in: "/linked"))
    }

    @Test("A loose object's filename does not prove that it is a commit.")
    func unreferencedObjectIDsAreRefused() {
        let object = "/repo/.git/objects/a1/b2c3d4e5f60718293a4b5c6d7e8f9012345678"
        let twin = "/repo/.git/objects/ff/00aa11bb22cc33dd44ee55ff6677889900aabb"
        let disk = FakeDisk(
            directories: [
                "/repo/.git/refs/heads", "/repo/.git/objects/a1", "/repo/.git/objects/ff",
                "/repo/.git/objects/pack",
            ],
            files: [
                object, twin, twin.replacingOccurrences(of: "00aa", with: "00ab"),
                "/repo/.git/objects/pack/pack-example.idx",
            ],
            executables: ["/usr/bin/git"])
        let check = TerminalLineCheck(files: disk)
        for line in [
            "git checkout a1b2c3d", "git checkout A1B2C3D", "git checkout a1b2c3d~1",
            "git checkout a1b2c3d4e5f60718293a4b5c6d7e8f9012345678", "git switch -d a1b2c3d",
            "git switch -c topic a1b2c3d", "git checkout -b topic a1b2",
        ] {
            #expect(!check.allows(line, in: "/repo"), "\(line)")
        }
        for line in [
            "git checkout a1b2c3e", "git checkout a1b", "git checkout ff00", "git checkout 0123abc",
            "git switch -d 9999999", "git switch a1b2c3d", "git checkout a1b2c3dz", "git checkout ../a1b2c3d",
        ] {
            #expect(!check.allows(line, in: "/repo"), "\(line)")
        }
        #expect(DestructiveCommand.matches("git checkout a1b2c3d -- .", failClosedOnUnresolved: true))
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
        for name in ["", "/main", "main/", "a..b", "a//b", "x.lock", "a b", "a:b", "a\u{1}b"] {
            #expect(!GitRepository.isRefName(name), "\(name)")
        }
    }

    @Test("Revision selectors are accepted only after a ref or HEAD.")
    func commitRevisionSelectors() {
        let repository = GitRepository.holding(api, files: project())
        #expect(repository?.hasCommit(named: "HEAD@{1}") == true)
        #expect(repository?.hasCommit(named: "@{-1}") == true)
        #expect(repository?.hasCommit(named: "main^{commit}") == true)
        #expect(repository?.hasCommit(named: "main@{0}^{tree}") == true)
        #expect(repository?.hasCommit(named: ":/message") == true)
        #expect(repository?.hasCommit(named: "missing@{1}") == false)
        #expect(repository?.hasCommit(named: "main^{unknown}") == false)
        #expect(repository?.hasCommit(named: "main@{}") == false)
        #expect(repository?.hasCommit(named: "main^{commit") == false)
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
