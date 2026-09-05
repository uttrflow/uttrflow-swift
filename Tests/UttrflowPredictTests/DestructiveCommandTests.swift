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
}
