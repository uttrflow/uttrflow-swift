import AppKit
import UttrflowUX
import Testing

@testable import Uttrflow

/// Asking the system for an icon cannot be tested here — this Mac's applications folder
/// is not the same as anybody else's. What can be, and what would go wrong quietly, is
/// the order the two lookups are tried in and how hard the answer is held on to: a row
/// redraws on every keystroke in a search field, so a lookup that is not remembered is a
/// walk through four directories per row per keystroke.
@MainActor
@Suite("The icon beside a dictation")
struct ApplicationIconsTests {
    private final class Counter {
        var identified: [String] = []
        var running: [String] = []
        var installed: [String] = []
    }

    private func icons(
        identified: [String: NSImage] = [:], running: [String: NSImage] = [:],
        installed: [String: NSImage] = [:]
    ) -> (ApplicationIcons, Counter) {
        let counter = Counter()
        let source = ApplicationIconSource(
            identified: { identifier in
                counter.identified.append(identifier)
                return identified[identifier]
            },
            running: { name in
                counter.running.append(name)
                return running[name]
            },
            installed: { name in
                counter.installed.append(name)
                return installed[name]
            })
        return (ApplicationIcons(source: source), counter)
    }

    private func app(_ name: String, identifier: String? = nil) -> HistoryApplication {
        HistoryApplication(
            name: name, initial: String(name.prefix(1)).uppercased(), identifier: identifier)
    }

    /// Told apart by size rather than by `NSImage.setName`: names are process-wide, and
    /// these suites run at the same time, so the second test to claim "running" would
    /// silently get an unnamed image.
    private func image(width: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: width, height: 1))
    }

    private let identifiedIcon: CGFloat = 1
    private let runningIcon: CGFloat = 2
    private let installedIcon: CGFloat = 3

    /// The identifier is the only lookup that cannot answer with the wrong app, so it
    /// goes first and the two name lookups are never reached.
    @Test("asks by bundle identifier first, and stops there")
    func prefersTheIdentifier() {
        let (icons, counter) = icons(
            identified: ["com.anthropic.claudefordesktop": image(width: identifiedIcon)],
            running: ["Claude": image(width: runningIcon)],
            installed: ["Claude": image(width: installedIcon)])

        let found = icons.icon(for: app("Claude", identifier: "com.anthropic.claudefordesktop"))

        #expect(found?.size.width == identifiedIcon)
        #expect(counter.running.isEmpty, "the identifier had already answered")
        #expect(counter.installed.isEmpty)
    }

    /// Every dictation recorded before identifiers were kept. The app somebody dictated
    /// into is usually still running, and a running app carries its icon with it — no
    /// directory to walk, and no chance of finding a different app of the same name
    /// somewhere else on the disk.
    @Test("falls back to the running app when there is no identifier")
    func prefersTheRunningApp() {
        let (icons, counter) = icons(
            running: ["Claude": image(width: runningIcon)],
            installed: ["Claude": image(width: installedIcon)])

        #expect(icons.icon(for: app("Claude"))?.size.width == runningIcon)
        #expect(counter.installed.isEmpty, "there was no reason to go looking on disk")
    }

    /// An app that has been deleted since: LaunchServices knows nothing about the
    /// identifier, and the name has to answer for it.
    @Test("falls back to the name when the identifier finds nothing")
    func fallsBackFromAMissingIdentifier() {
        let (icons, _) = icons(installed: ["Mail": image(width: installedIcon)])

        let found = icons.icon(for: app("Mail", identifier: "com.apple.mail.deleted"))

        #expect(found?.size.width == installedIcon)
    }

    /// The same app, once with an identifier and once without, must not share an answer:
    /// the first row looked up would otherwise decide what the second one draws.
    @Test("remembers the two lookups apart")
    func keysTheAnswersApart() {
        let (icons, _) = icons(
            identified: ["com.apple.mail": image(width: identifiedIcon)],
            installed: ["Mail": image(width: installedIcon)])

        #expect(
            icons.icon(for: app("Mail", identifier: "com.apple.mail"))?.size.width
                == identifiedIcon)
        #expect(icons.icon(for: app("Mail"))?.size.width == installedIcon)
    }

    @Test("goes looking on disk for an app that is not running")
    func fallsBackToTheDisk() {
        let (icons, _) = icons(installed: ["Mail": image(width: installedIcon)])

        #expect(icons.icon(for: app("Mail"))?.size.width == installedIcon)
    }

    /// An app that has since been deleted, or one whose bundle is not named as it
    /// presents itself. The row draws its lettered tile, which is what every row did
    /// before there were icons at all — a wrong icon would be worse than an initial.
    @Test("has no icon for an app this Mac has never heard of")
    func unknownApp() {
        let (icons, _) = icons()

        #expect(icons.icon(for: app("Nothing At All")) == nil)
    }

    @Test("remembers what it found")
    func remembersAHit() {
        let (icons, counter) = icons(running: ["Slack": image(width: runningIcon)])

        _ = icons.icon(for: app("Slack"))
        _ = icons.icon(for: app("Slack"))

        #expect(counter.running == ["Slack"])
    }

    /// The expensive answer to remember is the empty one: a miss is the case that walks
    /// every folder before giving up.
    @Test("remembers that it found nothing, so a miss costs one walk")
    func remembersAMiss() {
        let (icons, counter) = icons()

        _ = icons.icon(for: app("Ghost"))
        _ = icons.icon(for: app("Ghost"))

        #expect(counter.installed == ["Ghost"])
    }

    @Test("does not go looking for an app with no name")
    func ignoresAnEmptyName() {
        let (icons, counter) = icons()

        #expect(icons.icon(for: app("   ")) == nil)
        #expect(counter.running.isEmpty)
        #expect(counter.installed.isEmpty)
    }

    /// A name recorded with a stray space is the same app as one without.
    @Test("trims the name before asking")
    func trimsTheName() {
        let (icons, _) = icons(running: ["Notes": image(width: runningIcon)])

        #expect(icons.icon(for: app(" Notes "))?.size.width == runningIcon)
    }
}
