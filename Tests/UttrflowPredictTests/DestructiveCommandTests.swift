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
            "git clean -xdF", "diskutil eraseDisk APFS Disk disk4", "docker system prune -a",
            "docker volume rm data", "kubectl delete pod api", "terraform destroy",
            "terraform apply -destroy",
            "crontab -r", "mv secrets.txt /dev/null", "mkfs.apfs /dev/disk4",
        ])
    func recognisesEveryRoute(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line) should be destructive")
    }

    @Test(
        "Commands that only look like a destroying one are left alone.",
        arguments: [
            "git branch -d merged", "git branch --delete merged", "git restore --staged Sources",
            "git stash pop",
            "git checkout main", "git push origin main", "find . -name '*.swift'", "docker rm api",
            "kubectl get pods", "terraform plan", "crontab -l", "mv a b", "sudo", "xargs", "FOO=1",
            "diskutil list", "git clean -n",
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
}
