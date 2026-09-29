import Testing

@testable import UttrflowPredict

@Suite("Recognising a command that destroys")
struct DestructiveCommandTests {
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
            ":(){ :|:& };:",
        ])
    func recognisesDestructive(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
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
            "restart the staging database",
        ])
    func leavesOrdinaryAlone(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line) should be ordinary")
    }

    @Test(
        "A destroying command is recognised however it is reached or spelled.",
        arguments: [
            "/bin/rm -rf build", "\\rm -rf build", "sudo -E rm -rf /var", "sudo -u root rm -rf x",
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
            "ls 1> listing.txt", "make &> build.log", "echo x >notes.txt", "cat a.txt > b.txt && ls",
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
            "make 2> errors.log", "make 2>&1 | tee", "echo x >&2", "make > /dev/null",
            "make > /dev/null 2>&1", "echo x > /dev/stderr", "make &>> build.log", "sort < data.csv",
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
            #"mongosh mydb --eval "db.dropDatabase()""#, #"mongo mydb --eval "db.users.drop()""#,
            #"mongosh --eval "db.users.deleteMany({})""#, #"sqlite3 app.db "DELETE FROM users""#,
            #"psql -c "DELETE FROM users WHERE id = 1""#, "DELETE FROM users",
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
}
