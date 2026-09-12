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
