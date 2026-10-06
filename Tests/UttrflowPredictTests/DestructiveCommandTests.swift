import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Recognising a command that destroys")
struct DestructiveCommandTests {
    /// One destructive sample line for every program judged by its verbs, so a tool without a sample fails here.
    private static let verbToolSamples: [String: String] = [
        "kubectl": "kubectl -n prod delete pod api", "oc": "oc delete project p",
        "gh": "gh repo delete owner/repo", "aws": "aws s3 rb s3://bucket",
        "gcloud": "gcloud sql instances delete db", "az": "az group delete -n rg",
        "gsutil": "gsutil rm gs://bucket/x", "docker": "docker rm -f db", "podman": "podman rm -f db",
        "docker-compose": "docker-compose down -v", "podman-compose": "podman-compose down -v",
        "helm": "helm uninstall prod", "tmutil": "tmutil deletelocalsnapshots /",
        "launchctl": "launchctl bootout gui/501/com.example.agent", "npm": "npm unpublish pkg",
        "pnpm": "pnpm unpublish pkg", "yarn": "yarn unpublish pkg", "cargo": "cargo yank --version 1.0.0",
        "pip": "pip uninstall -y requests", "pip3": "pip3 uninstall -y requests",
        "brew": "brew uninstall --zap app", "defaults": "defaults delete com.example.app",
        "mysqladmin": "mysqladmin -u root drop db", "pulumi": "pulumi destroy -y",
        "heroku": "heroku apps:destroy -c app", "vercel": "vercel rm proj -y",
        "firebase": "firebase firestore:delete --all-collections", "sysadminctl": "sysadminctl -deleteUser u",
    ]

    @Test("Every program judged by its verbs has a destructive sample, and the sample is recognised.")
    func everyVerbToolHasASample() {
        #expect(Set(Self.verbToolSamples.keys) == DestructiveCommand.verbToolNames)
        for (tool, line) in Self.verbToolSamples {
            #expect(DestructiveCommand.matches(line), "\(tool): \(line)")
        }
    }

    @Test(
        "Whole command-line tools that destroy data are recognised, with their flag forms.",
        arguments: [
            "defaults delete com.example.app", "defaults -currentHost delete com.example.app key",
            "mysqladmin drop db", "mysqladmin -h db.example.com -u root drop db", "pulumi destroy -y",
            "pulumi -C infra destroy", "pulumi stack rm dev", "heroku apps:destroy -c app",
            "heroku pg:reset -a app", "vercel rm proj -y", "vercel remove proj",
            "firebase firestore:delete --all-collections", "firebase --project p database:remove /",
            "oc delete project p", "sysadminctl -deleteUser u", "sudo sysadminctl -deleteUser u -secure",
            "userdel -r u", "sudo userdel u",
        ])
    func wholeToolDestroyers(_ line: String) {
        #expect(DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line)")
    }

    @Test(
        "The same tools' reading verbs stay ordinary.",
        arguments: [
            "defaults read com.example.app", "defaults write com.example.app key -bool true",
            "mysqladmin status", "pulumi up", "pulumi stack ls", "heroku apps", "heroku logs -a app",
            "vercel ls", "vercel deploy", "firebase deploy", "oc get pods", "sysadminctl -addUser u",
        ])
    func wholeToolReaders(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line)")
    }

    @Test(
        "The commands that cannot be undone are recognised.",
        arguments: [
            "rm -rf /",
            "rm -rf node_modules",
            "sudo rm -rf /var",
            "rmdir important",
            "git push --force origin main",
            "git push -f",
            "git push origin +main",
            "git reset --hard HEAD~3",
            "git clean -fd",
            "DROP TABLE users",
            "drop database production",
            "TRUNCATE TABLE orders",
            "dd if=/dev/zero of=/dev/disk2",
            "mkfs.ext4 /dev/sdb",
            "cat ubuntu.img > /dev/rdisk4",
            "asr restore --source a.dmg --target /dev/rdisk2s1",
            "shutdown -h now",
            "reboot",
            "killall -9 Finder",
            "killall -KILL Finder",
            "killall -SIGKILL Finder",
            "killall -sigkill Finder",
            "killall -s SIGKILL Finder",
            "killall -sKILL Finder",
            "killall --signal=SIGKILL Finder",
            "pkill -9 -f node",
            "pkill -KILL node",
            "pkill -SIGKILL node",
            "pkill -s 9 node",
            "pkill -s SIGKILL node",
            "pkill -sKILL node",
            "pkill --signal=SIGKILL node",
            "kill -9 -1",
            "kill -KILL -1",
            "kill -SIGKILL 1234",
            "kill -sigkill 1234",
            "kill -s SIGKILL 1234",
            "kill -sKILL 1234",
            "kill --signal=SIGKILL 1234",
            ":(){ :|:& };:",
        ])
    func recognisesDestructive(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "Package removal commands are destructive, including when wrapped or preceded by options.",
        arguments: [
            "npm unpublish package@1.0.0 --force", "pnpm unpublish package", "yarn unpublish package",
            "cargo yank package --vers 1.0.0", "pip uninstall -y requests", "pip3 uninstall --yes requests",
            "brew uninstall --cask --zap app", "brew remove --zap app", "sudo npm unpublish package",
            "sudo pnpm unpublish package", "sudo yarn unpublish package",
            "sudo cargo yank package --vers 1.0.0",
            "sudo pip uninstall -y requests", "sudo pip3 uninstall --yes requests",
            "sudo brew uninstall --zap app",
            "sudo brew remove --zap app", "python -m pip uninstall -y requests",
            "python3 -m pip uninstall --yes requests", "python3.12 -m pip uninstall -y requests",
            "sudo python -m pip uninstall -y requests",
            "npm --registry https://registry.example unpublish package",
            "cargo --config config.toml yank package", "brew --repository /opt/homebrew uninstall --zap app",
        ])
    func recognisesIrreversiblePackageRemoval(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "Package-manager builds and installs remain ordinary, as do removals without irreversible options.",
        arguments: [
            "npm publish package", "cargo build", "pip install requests", "pip uninstall requests",
            "brew uninstall app", "brew remove app", "npm --registry unpublish publish",
            "cargo --config yank build", "pip uninstall -- -y", "brew uninstall -- --zap",
            "brew --repository uninstall install --zap app",
        ])
    func packageBuildsAndSafeOperationsRemainOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test(
        "Ordinary commands are left alone.",
        arguments: [
            "git commit -m 'work'",
            "git push origin feature",
            "git status",
            "ls -la",
            "SELECT * FROM users",
            "make verify",
            "npm run dev",
            "kill 1234",
            "kill -TERM 1234",
            "kill -s SIGTERM 1234",
            "kill --signal=SIGTERM 1234",
            "pkill node",
            "pkill -TERM -f node",
            "killall Finder",
            "killall -TERM Finder",
            "restart the staging database",
        ])
    func leavesOrdinaryAlone(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test(
        "Argument consumers and package-manager removals remain ordinary.",
        arguments: [
            "echo rm", "echo please rm this", "man rm", "which dd", "tldr shred", "type rm",
            "help rm", "info dd", "whatis rm", "apropos shred", "printf rm", "command -v rm",
            "command -V dd",
            "npm rm lodash", "pnpm remove lodash", "yarn remove lodash",
        ])
    func leavesHarmlessDestroyerNamesAlone(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test(
        "A destroying command is recognised however it is reached or spelled.",
        arguments: [
            "/bin/rm -rf build", "\\rm -rf build", "sudo -E rm -rf /var", "sudo -u root rm -rf x",
            "command rm -rf x",
            "FOO=1 rm -rf x", "env -i rm x", "nice -n 10 rm x", "find . -name '*.log' | xargs -n 1 rm",
            "find . -type f -delete", "find . -exec rm {} +", "srm secret.txt", "unlink file",
            "git push --force-with-lease", "git push origin --delete feature", "git push origin :feature",
            "git push -d origin feature", "git branch -D feature", "git branch -dD x",
            "git branch --delete --force feature", "git stash drop", "git stash clear", "git checkout -- .",
            "git checkout .", "git restore Sources", "git restore --staged --worktree x", "git clean --force",
            "git clean -xdF", "diskutil eraseDisk APFS Disk disk4", "diskutil apfs deleteVolume disk1s5",
            "diskutil apfs deleteContainer disk1", "diskutil apfs eraseVolume disk1s5",
            "docker system prune -a",
            "docker volume rm data", "kubectl delete pod api", "terraform destroy",
            "terraform apply -destroy",
            "crontab -r", "mv secrets.txt /dev/null", "mkfs.apfs /dev/disk4",
        ])
    func recognisesEveryRoute(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "A quoted assignment in front does not hide the command, and a quoted carried line is still read.",
        arguments: [
            #"MSG="a b" rm -rf x"#, #"env MSG="a b" rm -rf x"#, #"sudo -E PATH="/a b:$PATH" rm -rf x"#,
            "ssh host 'rm -rf x'",
        ])
    func recognisesPastQuotedAssignments(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "Mercurial history removal and destructive updates are recognised.",
        arguments: [
            "hg strip -r 3", "hg prune --rev 3", "hg purge", "hg purge --all", "hg update -C",
            "hg update --clean", "hg -R repo strip -r 3", "hg --config ui.merge=internal:fail update -C",
            "sudo hg strip -r 3", "env HGPLAIN=1 hg purge",
        ])
    func recognisesDestructiveMercurial(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "Subversion deletion aliases and revert are recognised.",
        arguments: [
            "svn delete https://svn.example.com/repo/trunk -m x", "svn del file", "svn remove file",
            "svn rm file", "svn revert -R .", "svn --username alice delete URL",
            "sudo svn revert -R .",
        ])
    func recognisesDestructiveSubversion(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "Non-destructive Mercurial and Subversion commands remain ordinary.",
        arguments: [
            "hg log", "hg --config ui.verbose=true log", "hg update", "hg update -- -C", "svn status",
            "svn --username alice status",
        ])
    func keepsOrdinaryMercurialAndSubversionCommands(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test(
        "Quoting or escaping the executable does not hide a destructive command.",
        arguments: [
            #""rm" -rf build"#, "'rm' -rf build", #"r\m -rf build"#,
            #"sudo "rm" -rf build"#, "env FOO=1 'rm' build", #"find . -exec "rm" {} +"#,
        ])
    func quotedDestroyers(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "Recursive permission and ownership changes are destructive, including clustered flags.",
        arguments: [
            "chmod -R 000 ~", "chmod --recursive 000 /", "chmod -vfR 000 tree", "chown -R nobody /",
            "chown -vR nobody /", "chgrp --recursive staff /", "sudo chgrp -hR staff tree",
        ])
    func recursivePermissionAndOwnershipChanges(_ line: String) {
        #expect(DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line)")
    }

    @Test(
        "Non-recursive permission and ownership changes remain ordinary.",
        arguments: [
            "chmod +x script.sh", "chmod 600 ~/.ssh/config", "chown nobody file", "chgrp staff file",
            "chmod -- -R",
        ])
    func nonRecursivePermissionAndOwnershipChanges(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line)")
    }

    @Test(
        "Quoted ordinary commands and quoted separators are not destructive.",
        arguments: [
            #""ls" -la"#, "'git' status", #"echo "rm -rf /""#,
            #"echo "done; rm -rf build""#,
        ])
    func quotedOrdinaryCommands(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test("Unresolved terminal syntax is refused without treating ordinary prose as destructive.")
    func unresolvedSyntax() {
        #expect(DestructiveCommand.matches(#""$COMMAND" -rf build"#, failClosedOnUnresolved: true))
        #expect(DestructiveCommand.matches("echo $(rm -rf build)", failClosedOnUnresolved: true))
        #expect(DestructiveCommand.matches("git push $FLAGS", failClosedOnUnresolved: true))
        #expect(!DestructiveCommand.matches("The result (if available) is ready."))
        #expect(!DestructiveCommand.matches("SELECT * FROM users"))
        #expect(!DestructiveCommand.matches(#""ls" build"#, failClosedOnUnresolved: true))
    }

    @Test(
        "Commands that only look like a destroying one are left alone.",
        arguments: [
            "git branch -d merged", "git branch --delete merged", "git restore --staged Sources",
            "git stash pop",
            "git checkout main", "git push origin main", "find . -name '*.swift'", "docker rm api",
            "kubectl get pods", "terraform plan", "crontab -l", "mv a b", "sudo", "xargs", "FOO=1",
            "diskutil list", "diskutil apfs list", "git clean -n",
        ])
    func leavesLookalikesAlone(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test(
        "Forced branch deletions are destructive regardless of short or long flag spelling.",
        arguments: [
            "git branch -d -f topic", "git branch -df topic", "git branch -fd topic",
            "git branch --delete -f topic", "git branch -d --force topic",
        ])
    func recognisesForcedBranchDeletion(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test("Deleting a merged branch without force remains ordinary.")
    func leavesUnforcedBranchDeletionAlone() {
        #expect(!DestructiveCommand.matches("git branch -d topic"))
    }

    @Test(
        "Copying a device stream over a file is destructive.",
        arguments: [
            "cp /dev/null notes.txt", "cp -f /dev/null notes.txt", "cp -- /dev/null notes.txt",
            "cp /dev/zero notes.txt", "cp -p /dev/zero notes.txt", "cp -t output /dev/null",
            "cp --target-directory=output /dev/zero",
        ])
    func copyingDeviceStreamsIsDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "Copying ordinary files is not destructive.",
        arguments: [
            "cp a.txt b.txt", "cp -p a.txt b.txt", "cp -- a.txt b.txt", "cp -S /dev/null a.txt b.txt",
            "cp -t output a.txt", "cp -S -t a.txt b.txt", "cp -- -tname a.txt", "cp a.txt /dev/null",
            "cp a.txt /dev/zero", "cp --suffix=/dev/null a.txt b.txt", "cp -S/dev/null a.txt b.txt",
        ])
    func copyingOrdinaryFilesIsOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    /// The destroying command is not the one the line begins with, and it is still the one that runs.
    @Test(
        "A destroying command behind a harmless one is still recognised.",
        arguments: [
            "npm run build && git push --force origin main",
            "cd /tmp; rm -rf work",
            "echo going | sudo shutdown -h now",
        ])
    func readsEveryClause(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) destroys in a later clause")
    }

    /// The flag and the word belong to different commands, so neither vouches for the other.
    @Test(
        "Words from one command do not make another destructive.",
        arguments: [
            "git status && ls -lf clean",
            "git log --oneline && rm_nothing",
            "echo 'git push --force' >> notes.md",
        ])
    func keepsClausesApart(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) destroys nothing")
    }

    @Test func sqlWordsInAnUnrelatedCommandAreNotDestructive() {
        #expect(!DestructiveCommand.matches("echo Please drop the users table before you truncate the log"))
        #expect(!DestructiveCommand.matches("git commit -m Drop the staging database index"))
        #expect(!DestructiveCommand.matches("grep truncate notes.txt"))
    }

    @Test func gitJudgesOnlyTheSubcommandAtTheHeadOfTheClause() {
        for command in [
            "git commit -m checkout .", "git commit -m reset --hard", "git log --grep push -f",
            "git add clean -f", "git commit -m stash drop",
        ] {
            #expect(!DestructiveCommand.matches(command), "\(command)")
        }
        for command in ["git -C repo checkout .", "git -c core.x=y reset --hard", "git --no-pager push -f"] {
            #expect(DestructiveCommand.matches(command), "\(command)")
        }
    }

    @Test func sqlGivenToADatabaseClientIsDestructive() {
        #expect(DestructiveCommand.matches("psql -c \"DROP TABLE users;\""))
        #expect(DestructiveCommand.matches("mysql -e \"TRUNCATE logs\""))
        #expect(DestructiveCommand.matches("sudo sqlite3 app.db 'drop index idx_users'"))
        #expect(DestructiveCommand.matches("ALTER TABLE users DROP COLUMN email"))
    }

    @Test func aShellRunningAStringIsJudgedByThatString() {
        #expect(DestructiveCommand.matches("sh -c \"rm -rf ~\""))
        #expect(DestructiveCommand.matches("bash -c 'dd if=/dev/zero of=/dev/disk2'"))
        #expect(DestructiveCommand.matches("zsh -c 'git reset --hard'"))
        #expect(DestructiveCommand.matches("sudo /bin/bash -lc \"rm -rf build\""))
        #expect(DestructiveCommand.matches("nohup sh -c 'shred notes.txt'"))
        #expect(!DestructiveCommand.matches("sh -c \"echo hi\""))
        #expect(!DestructiveCommand.matches("bash script.sh"))
    }

    @Test func kubectlDeleteIsFoundPastGlobalFlags() {
        #expect(DestructiveCommand.matches("kubectl -n production delete deployment critical-app"))
        #expect(DestructiveCommand.matches("kubectl --context=prod delete namespace staging"))
        #expect(DestructiveCommand.matches("kubectl --kubeconfig ~/.kube/alt -v 6 delete pod api"))
        #expect(DestructiveCommand.matches("kubectl delete pod api"))
        #expect(!DestructiveCommand.matches("kubectl -n production get pods"))
        #expect(!DestructiveCommand.matches("kubectl -n delete get pods"))
        #expect(!DestructiveCommand.matches("kubectl get pod delete"))
    }

    @Test(
        "A switch that throws away uncommitted changes is destructive, however its flags are written.",
        arguments: [
            "git switch -f main", "git switch --force main", "git switch --discard-changes main",
            "git switch -fc topic", "git switch -qf main", "git -C repo switch -f main",
            "git -c core.x=y switch --discard-changes main", "sudo git switch --force main",
        ])
    func forcedSwitchIsDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A switch that keeps the working tree is ordinary, even where a branch name holds an f.",
        arguments: [
            "git switch main", "git switch -c new", "git switch -c fix-login", "git switch -cfix-login",
            "git switch -C feature", "git switch --detach v1.0", "git switch -", "git checkout -bfeature",
            "git commit -m 'switch -f later'",
        ])
    func ordinarySwitchIsLeftAlone(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "Worktree, rm and forced submodule deinit throw work away, every flag spelling.",
        arguments: [
            "git worktree remove ../wt", "git worktree remove --force ../wt",
            "git worktree remove -f ../wt", "git worktree remove --force",
            "git -C repo worktree remove -f ../wt", "sudo git worktree remove ../wt",
            "git rm file", "git rm -f file", "git rm --force file",
            "git rm -rf file", "git rm -f Sources/App/Main.swift",
            "git -C repo rm -f secret", "sudo git rm -f file",
            "git submodule deinit -f path", "git submodule deinit --force path",
            "git submodule deinit -f", "git -C repo submodule deinit -f path",
            "sudo git submodule deinit --force path",
        ])
    func forcedGitOperationsAreDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "Unforced submodule deinit and ordinary git worktree reads stay ordinary.",
        arguments: [
            "git worktree list", "git worktree add ../wt", "git worktree prune",
            "git submodule deinit path", "git submodule deinit --all",
            "git submodule status", "git submodule init path", "git rm --cached file",
        ])
    func unforcedSubmoduleAndWorktreeReadsStayOrdinary(_ line: String) {
        #expect(
            !DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test func pathOnlyCheckoutIsDestructiveWhenTheFileExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "checkout-4408-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "App.swift")
        try Data("x".utf8).write(to: file)
        let path = file.path(percentEncoded: false)
        #expect(DestructiveCommand.matches("git checkout \(path)", failClosedOnUnresolved: true))
        #expect(DestructiveCommand.matches("git -C repo checkout \(path)", failClosedOnUnresolved: true))
        #expect(
            !DestructiveCommand.matches(
                "git checkout missing-\(UUID().uuidString).swift", failClosedOnUnresolved: true))
        #expect(!DestructiveCommand.matches("git checkout main", failClosedOnUnresolved: true))
    }

    @Test(
        "An rsync that deletes files is destructive, whichever delete flag it carries.",
        arguments: [
            "rsync -a --delete src/ backup/", "rsync -a --delete-after src/ backup/",
            "rsync -a --delete-excluded src/ backup/", "rsync -a --delete-before src/ backup/",
            "rsync -a --delete-during src/ backup/", "rsync -a --delete-delay src/ backup/",
            "rsync -a --del src/ backup/", "rsync -a --remove-source-files src/ backup/",
            "sudo rsync -av --delete ~/work/ /Volumes/backup/work/",
        ])
    func deletingRsyncIsDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "An output redirection that empties a file first is destructive.",
        arguments: [
            "echo x > notes.txt", "echo \"\" > notes.txt", "> notes.txt", "sort data.csv >| data.csv",
            "ls 1> listing.txt", "make 2> errors.log", "make 3> trace.log", "make 2>| errors.log",
            "make &> build.log", "echo x >notes.txt", "cat a.txt > b.txt && ls",
            "make 2>&1 | tee build.log", "make >& build.log", "make >&build.log",
            "ls -la >&listing.txt && ls",
        ])
    func truncatingRedirectionIsDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "An rsync that deletes nothing, and a redirection that empties no file, are ordinary.",
        arguments: [
            "rsync -a src dst", "rsync -av --progress src/ backup/", "echo x >> notes.txt",
            "make 2>&1 | tee", "make 3>&2", "echo x >&2", "make > /dev/null",
            "make 2> /dev/null", "make 3>| /dev/stderr", "make > /dev/null 2>&1",
            "echo x > /dev/stderr", "make &>> build.log", "sort < data.csv",
            "grep '>' notes.txt", "make | tee -a build.log", "make | tee --append build.log", "make | tee",
            "make >&2", "make 1>&-", "make >& /dev/null", "make >>& build.log",
        ])
    func harmlessRsyncAndRedirectionAreOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A destroying command behind a wrapper that runs it is recognised, past the wrapper's flags and values.",
        arguments: [
            "timeout 60 rm -rf build", "timeout -s KILL 60 rm -rf build", "timeout -k 5 10 rm x",
            "gtimeout 60 rm -rf build", "caffeinate rm -rf ~/scratch", "caffeinate -i -t 600 rm -rf build",
            "watch -n1 rm x", "watch -n 5 rm x", "ionice -c 3 rm -rf build", "chronic rm -rf build",
            "unbuffer rm -rf build", "stdbuf -oL rm -rf build", "stdbuf -o L rm -rf build",
            "taskpolicy -c background rm -rf build", "arch -x86_64 rm -rf build",
            "arch -arch arm64 rm -rf build", "flock /tmp/lock rm -rf build", "flock -w 5 /tmp/lock rm x",
            "chroot /srv/jail rm -rf /data", "pkexec rm -rf /opt/app", "nice timeout 60 rm -rf build",
        ])
    func wrappedDestroyers(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A wrapper running an ordinary command is ordinary, its duration or file never read as the command.",
        arguments: [
            "timeout 5 ls", "timeout 60 make verify", "caffeinate -d", "caffeinate make build",
            "watch -n1 git status", "flock /tmp/rm ls", "chroot /srv/rm ls", "stdbuf -oL tail log.txt",
        ])
    func wrappedOrdinaryCommands(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "Carriers that re-parse or pass through to the command they carry are judged by it.",
        arguments: [
            "eval \"rm -rf ~\"", "eval 'rm -rf ~/Documents'", "eval \"dd if=/dev/zero of=/dev/disk2\"",
            "setsid rm -rf build", "setsid dd if=/dev/zero of=/dev/disk2",
            "parallel rm -rf ~/Documents", "parallel -j 4 rm -rf ~/Documents",
            "su -c \"rm -rf ~\"", "su -c 'rm -rf /var'", "su -c \"dd if=/dev/zero of=/dev/disk2\"",
            "runuser -c \"rm -rf ~\"", "runuser -c 'rm -rf /tmp'",
            "sudo eval \"rm -rf ~\"", "nice eval \"rm -rf x\"",
        ])
    func carrierCarriesDestroyer(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "Carriers carrying an ordinary command are ordinary.",
        arguments: [
            "eval \"echo hi\"", "eval 'ls -la'", "eval \"date\"",
            "setsid ls", "setsid make verify", "setsid date",
            "parallel ls", "parallel -j 4 ls", "parallel echo done",
            "su -c \"echo hi\"", "su -c 'ls -la'", "su alice -c \"echo hi\"",
            "runuser -c \"echo hi\"", "runuser -c 'ls'",
        ])
    func carrierCarriesOrdinary(_ line: String) {
        #expect(
            !DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "An unknown carrier word followed by a destroyer fails closed, never reaching the carrier as the command.",
        arguments: [
            "unknown-wrapper rm -rf build", "fakecarrier dd if=/dev/zero of=/dev/disk2",
        ])
    func unknownCarrierFailsClosed(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A destroying command after a shell reserved word is recognised, in a loop, a condition or a negation.",
        arguments: [
            #"for f in *.log; do rm -rf "$f"; done"#, "if true; then rm -rf build; fi",
            "if [ -d x ]; then ls; else rm -rf build; fi", "if false; then ls; elif true; then rm -rf x; fi",
            "! rm -rf dist", "if rm -rf build; then echo gone; fi", "while true; do rm x; done",
            "until false; do rm x; done", "while sudo rm -rf x; do sleep 1; done",
            "for b in a b; do git branch -D $b; done",
        ])
    func destroyersAfterReservedWords(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "A loop or a condition whose commands destroy nothing is ordinary.",
        arguments: [
            "for f in a b; do echo $f; done", "if true; then ls; fi", "! grep -q x notes.txt",
            "while true; do date; done",
        ])
    func ordinaryCompoundCommands(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test(
        "A push that deletes or rewrites remote refs the local repository lacks is destructive.",
        arguments: [
            "git push --mirror origin", "git push --mirror", "git push --prune origin",
            "git push --prune origin refs/heads/*:refs/heads/*", "git -C repo push --mirror backup",
        ])
    func mirroringPushIsDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A fetch that prunes and a push naming its refs plainly are ordinary.",
        arguments: [
            "git fetch --prune", "git fetch --prune origin", "git remote prune origin",
            "git push origin main",
        ])
    func pruningFetchIsOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A push whose force or delete flag sits inside a short-flag cluster is destructive.",
        arguments: [
            "git push -fu origin feature", "git push -uf origin feature",
            "git push -fd origin feature", "git push -vf origin feature",
            "git push -df origin feature", "git push -fv origin feature",
            "git -C repo push -fu origin feature",
        ])
    func clusteredPushFlagIsDestructive(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "A push whose only short flag is a harmless one is ordinary.",
        arguments: [
            "git push -u origin feature", "git push -v origin feature", "git push -q origin feature",
        ])
    func harmlessPushClusterIsOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test(
        "A cloud or hosting tool deleting a repository, a release, a bucket or a resource is destructive.",
        arguments: [
            "gh repo delete example/demo --yes", "gh release delete v1.0",
            "gh release delete-asset v1.0 app.zip",
            "gh -R example/demo release delete v1.0", "gh secret delete TOKEN", "gh api -X DELETE repos/o/r",
            "gh api --method DELETE repos/o/r", "sudo gh repo delete example/demo",
            "aws s3 rm s3://example-bucket --recursive", "aws s3 rm s3://example-bucket/key.txt",
            "aws s3 rb s3://example-bucket --force",
            "aws --profile prod s3 rm s3://example-bucket --recursive",
            "aws --region eu-west-1 s3 rb s3://example-bucket", "aws s3 sync . s3://example-bucket --delete",
            "aws s3api delete-bucket --bucket example-bucket",
            "aws ec2 terminate-instances --instance-ids i-1",
            "aws rds delete-db-instance --db-instance-identifier db",
            "timeout 60 aws s3 rm s3://b --recursive",
            "gcloud compute instances delete vm-1", "gcloud --project demo sql instances delete db",
            "az group delete --name demo", "az -o json vm delete -g demo -n vm1", "gsutil rm gs://example/x",
            "gsutil -m rm -r gs://example", "gsutil rb gs://example", "gsutil rsync -d src gs://example",
        ])
    func cloudDeletionsAreDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "An AWS operation named outside the delete- or terminate- prefixes but irreversible in fact is destructive.",
        arguments: [
            "aws kms schedule-key-deletion --key-id K --pending-window-in-days 7",
            "aws ec2 deregister-image --image-id ami-0",
            "aws kms disable-key --key-id K",
            "aws ec2 remove-tags --resources i-1 --tags Key=env",
            "aws sqs purge-queue --queue-url https://sqs.example.com/q",
            "aws ecr batch-delete-image --repository-id r --image-ids imageDigest=0",
        ])
    func awsIrreversibleNamedOperationsAreDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "gcloud and az destructive verbs other than `delete` are destructive when they remove, purge or batch-delete.",
        arguments: [
            "gcloud storage rm -r gs://prod-bucket",
            "gcloud services purge disabled-service.googleapis.com",
            "az storage blob delete-batch -s c --account-name a",
            "az keyvault purge --name v",
        ])
    func cloudNonDeleteVerbsAreDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "gsutil rsync with the delete flag inside a short-flag cluster is destructive.",
        arguments: [
            "gsutil rsync -dr src gs://example",
            "gsutil rsync -rd src gs://example",
            "gsutil rsync -mdr src gs://example",
            "gsutil -m rsync -dr src gs://example",
        ])
    func gsutilRsyncClusteredDeleteIsDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "gsutil rsync without the delete flag, including a plain -r cluster, is ordinary.",
        arguments: [
            "gsutil rsync -r src gs://example",
            "gsutil rsync src gs://example",
            "gsutil -m rsync -r src gs://example",
        ])
    func gsutilRsyncWithoutDeleteIsOrdinary(_ line: String) {
        #expect(
            !DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A cloud or hosting tool that only reads or creates is ordinary.",
        arguments: [
            "gh repo view example/demo", "gh release list", "gh pr create --title delete", "gh api repos/o/r",
            "aws s3 ls", "aws s3 ls s3://example-bucket/rm", "aws s3 cp a.txt s3://example-bucket",
            "aws s3 sync . s3://example-bucket", "aws --region delete-me s3 ls", "aws ec2 describe-instances",
            "gcloud compute instances list", "az group list", "gsutil ls gs://example",
        ])
    func cloudReadsAreOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A git command that rewrites history or deletes its recovery path is destructive.",
        arguments: [
            "git filter-branch --force --index-filter 'git rm --cached secret' HEAD",
            "git filter-branch -f HEAD",
            "git filter-repo --path secret --invert-paths", "git update-ref -d refs/heads/feature",
            "git update-ref --delete refs/heads/feature", "git reflog expire --expire=now --all",
            "git reflog delete HEAD@{1}", "git gc --prune=now", "git gc --aggressive --prune=all",
            "git prune",
            "git -C repo reflog expire --expire=now --all", "git -C repo filter-repo --invert-paths --path a",
            "git -C repo gc --prune=now",
        ])
    func historyDestroyingGitIsDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A git command that only reads or tidies history is ordinary.",
        arguments: [
            "git gc", "git gc --aggressive", "git reflog", "git reflog show main",
            "git update-ref refs/heads/x HEAD",
            "git remote prune origin", "git worktree prune", "git log --grep filter-branch",
        ])
    func historyReadingGitIsOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A datastore command that drops a database or deletes its data is destructive.",
        arguments: [
            "dropdb mydb", "dropdb -h db.example.com mydb", "dropuser app", "redis-cli FLUSHALL",
            "redis-cli -h cache.example.com -n 2 flushdb", "valkey-cli flushall",
            "DROP KEYSPACE app", "DROP VIEW users", "DROP MATERIALIZED VIEW events_mv", "DROP USER app",
            "DROP ROLE analyst", "DROP TYPE mood", "DROP FUNCTION score", "DROP PROCEDURE refresh",
            #"mongosh mydb --eval "db.dropDatabase()""#, #"mongo mydb --eval "db.users.drop()""#,
            #"mongosh --eval "db.users.deleteMany({})""#, #"sqlite3 app.db "DELETE FROM users""#,
            #"psql -c "DELETE FROM users WHERE id = 1""#, "DELETE FROM users",
            #"cqlsh -e "DROP KEYSPACE app""#,
            #"clickhouse-client -q "ALTER TABLE logs DELETE WHERE 1""#,
            #"clickhouse-client -q "ALTER TABLE logs DROP PARTITION '2026-10'""#,
        ])
    func datastoreDeletionsAreDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A datastore command that only reads or writes is ordinary.",
        arguments: [
            #"psql -c "select 1""#, "redis-cli get k", "redis-cli info", #"mongosh --eval "db.users.find()""#,
            #"sqlite3 app.db "SELECT * FROM users""#, "createdb mydb",
            #"clickhouse-client -q "SELECT * FROM logs""#,
        ])
    func datastoreReadsAreOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A container or release command that removes workloads or their data is destructive.",
        arguments: [
            "docker rm -f db", "docker rm -fv db", "docker container rm -f db", "docker rmi -f app:latest",
            "docker image rm --force app", "docker compose down -v",
            "docker compose -f prod.yml down --volumes",
            "docker-compose down -v", "podman rm -f db", "docker -c remote rm -f db", "docker volume rm data",
            "docker system prune -a", "helm uninstall prod", "helm delete prod", "helm -n prod uninstall api",
            "helm --kube-context prod uninstall api",
        ])
    func workloadRemovalIsDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A container or release command that lists, runs or stops is ordinary.",
        arguments: [
            "docker ps", "docker rm db", "docker container rm db", "docker run --rm -it app",
            "docker rmi app:old", "docker compose down",
            "docker compose up -d", "docker-compose down", "podman images", "helm list", "helm -n prod list",
            "helm upgrade --install api ./chart",
        ])
    func workloadReadsAreOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A system command that deletes backups or removes a service is destructive.",
        arguments: [
            "sudo tmutil delete -d /Volumes/Backup -t 2026-09-01-120000", "tmutil deletelocalsnapshots /",
            "sudo tmutil thinlocalsnapshots / 10000000000 4", "launchctl remove com.example.agent",
            "sudo launchctl bootout system/com.example.daemon",
            "launchctl unload ~/Library/LaunchAgents/x.plist",
        ])
    func systemRemovalIsDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A system command that only reads or starts is ordinary.",
        arguments: [
            "tmutil listbackups", "tmutil listlocalsnapshots /", "tmutil status", "launchctl list",
            "launchctl print system/com.example.daemon", "launchctl load /Library/LaunchAgents/x.plist",
        ])
    func systemReadsAreOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "Every find action clause is judged, in any order, and any of -ok or -okdir is recognised.",
        arguments: [
            "find . -name '*.log' -exec echo {} \\; -exec rm -rf {} \\;",
            "find . -exec echo {} \\; -exec rm -rf {} \\;",
            "find . -exec echo {} \\; -exec rm {} +",
            "find . -ok rm -rf {} \\;",
            "find . -okdir rm -rf {} \\;",
            "find . -exec rm -rf {} \\; -exec echo {} \\;",
            "find . -exec echo {} + -exec rm -rf {} +",
        ])
    func everyFindActionClauseIsJudged(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "A find whose every action clause is ordinary stays ordinary, however many -exec it stacks.",
        arguments: [
            "find . -name '*.log' -exec echo {} \\;",
            "find . -exec echo {} \\; -exec ls {} \\;",
            "find . -exec ls {} + -exec echo {} \\;",
            "find . -ok ls {} \\;",
            "find . -okdir ls {} \\;",
        ])
    func ordinaryFindActionClausesStayOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    /// The form `carrier host [flags] destroyer [args]` is judged by the carried destroyer with the same rules as a local one.
    @Test(
        "A remote shell carrier that runs a destroying command is recognised, with each destroyer spelled out.",
        arguments: [
            "ssh prod rm -rf /srv/app",
            "ssh user@host dd if=/dev/zero of=/dev/disk2",
            "ssh prod mkfs.ext4 /dev/sdb",
            "ssh -i ~/.ssh/id_ed25519 prod rm -rf /srv/app",
            "ssh -p 2222 prod rm -rf build",
            "sudo ssh prod rm -rf /srv/app",
            "mosh host rm -rf /srv/app",
            "mosh user@host dd if=/dev/zero of=/dev/disk2",
        ])
    func remoteCarriersCarryingDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A remote shell carrier with no command or with an ordinary command is ordinary.",
        arguments: [
            "ssh prod",
            "ssh user@host ls",
            "ssh -p 2222 prod cat /etc/hostname",
            "mosh host",
            "mosh user@host uname -a",
        ])
    func remoteCarriersWithOrdinaryCommandsAreOrdinary(_ line: String) {
        #expect(
            !DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A parallel runner that executes a destroyer is recognised.",
        arguments: [
            "parallel rm -rf /data",
            "parallel -j 8 rm -rf /data",
            "parallel --jobs 4 rm -rf /data",
            "parallel dd if=/dev/zero of=/dev/disk2",
            "parallel mkfs.ext4 /dev/sdb",
        ])
    func parallelCarryingDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A destroyer carried as a quoted command line is judged as that line, at any depth.",
        arguments: [
            "ssh host 'rm -rf x'",
            "ssh -p 2222 host \"rm -rf /srv/app\"",
            "ssh host \"sh -c 'rm -rf x'\"",
            "parallel 'rm -rf /data'",
            "docker exec c sh -c 'rm -rf /'",
            "podman exec -it c bash -c 'shred notes.txt'",
            "kubectl exec p -- sh -c 'rm -rf /var/lib'",
            "fd -x sh -c 'rm -rf {}'",
            "fd -e log -x sh -c 'rm -f {}'",
        ])
    func quotedCarriedCommandIsJudged(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "An ordinary command carried as a quoted line stays ordinary.",
        arguments: [
            "ssh host 'ls -la'",
            "ssh host \"echo 'rm -rf x'\"",
            "docker exec c sh -c 'echo hi'",
            "kubectl exec p -- sh -c 'cat /etc/hostname'",
            "fd -x sh -c 'wc -l {}'",
        ])
    func quotedOrdinaryCarriedCommandIsOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test(
        "A parallel runner with no command or with an ordinary command is ordinary.",
        arguments: [
            "parallel --citation",
            "parallel -j 8",
            "parallel ls",
            "parallel 'echo hello'",
        ])
    func parallelWithOrdinaryCommandsIsOrdinary(_ line: String) {
        #expect(
            !DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "An fd runner with -x, -X, --exec, --exec-batch or --run is judged by the command it carries.",
        arguments: [
            "fd -x rm -rf {}",
            "fd -X rm -rf {}",
            "fd --exec rm -rf {}",
            "fd --exec-batch rm -rf {}",
            "fd --run rm -rf {}",
            "fd pattern -x rm -rf {}",
            "fd -e txt -x rm -rf {}",
            "fd pattern -X dd if=/dev/zero of=/dev/disk2",
            "fd -e txt --exec mkfs.ext4 /dev/sdb",
            "sudo fd -x rm -rf {}",
        ])
    func fdCarryingDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "An fd runner with no command or with an ordinary command is ordinary.",
        arguments: [
            "fd pattern",
            "fd -e txt",
            "fd -x ls",
            "fd --exec ls",
            "fd pattern -x ls",
        ])
    func fdWithOrdinaryCommandsIsOrdinary(_ line: String) {
        #expect(
            !DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A docker exec or run that destroys inside a container is recognised.",
        arguments: [
            "docker exec db rm -rf /var/lib/postgresql/data",
            "docker exec db dd if=/dev/zero of=/dev/disk2",
            "docker exec db mkfs.ext4 /dev/sdb",
            "docker exec -it db rm -rf /var/lib/postgresql/data",
            "docker exec -u postgres db rm -rf /var/lib/postgresql/data",
            "docker exec -w /tmp db rm -rf /data",
            "docker exec -e KEY=VAL db rm -rf /data",
            "docker run --rm app rm -rf /tmp/work",
            "docker run -it app dd if=/dev/zero of=/dev/disk2",
            "sudo docker exec db rm -rf /var/lib/postgresql/data",
            "podman exec db rm -rf /data",
            "podman run --rm app rm -rf /tmp/work",
        ])
    func containerExecCarryingDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A docker exec or run that only runs an ordinary command is ordinary.",
        arguments: [
            "docker exec db ls",
            "docker exec -it db bash",
            "docker exec db psql",
            "docker run --rm app ls /data",
            "podman exec db bash",
            "podman run --rm app env",
        ])
    func containerExecWithOrdinaryCommandsIsOrdinary(_ line: String) {
        #expect(
            !DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }

    @Test(
        "A kubectl exec that runs a destroyer in a pod is recognised.",
        arguments: [
            "kubectl exec pod -- rm -rf /data",
            "kubectl exec pod -- dd if=/dev/zero of=/dev/disk2",
            "kubectl exec pod -- mkfs.ext4 /dev/sdb",
            "kubectl exec -n production pod -- rm -rf /data",
            "kubectl exec -c container mypod -- rm -rf /data",
            "kubectl exec -it pod -- rm -rf /data",
            "sudo kubectl exec pod -- rm -rf /data",
        ])
    func kubectlExecCarryingDestructive(_ line: String) {
        #expect(
            DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be destructive")
    }

    @Test(
        "A kubectl exec that only runs an ordinary command is ordinary.",
        arguments: [
            "kubectl exec pod -- ls",
            "kubectl exec -it pod -- bash",
            "kubectl exec pod -- psql",
            "kubectl exec -n production pod -- env",
        ])
    func kubectlExecWithOrdinaryCommandsIsOrdinary(_ line: String) {
        #expect(
            !DestructiveCommand.matches(line, failClosedOnUnresolved: true), "\(line) should be ordinary")
    }
}
