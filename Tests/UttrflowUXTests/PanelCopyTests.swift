import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// The panel shipped, briefly, saying "Clipboard history is synced across devices" under
/// a tick. Nothing syncs: the clipboard is one JSON file in Application Support, and this
/// is a product whose whole argument is that what you copy stays where you copied it.
///
/// The sentence was hardcoded in the SwiftUI view rather than decided in the presentation,
/// which is why no test saw it. These read every word the panel can say, from the one
/// place that decides them.
@Suite("What the panel claims about itself")
struct PanelCopyTests {
    /// Every user-facing string a panel can produce, across the states that change them.
    static func everyPanelString() -> [String] {
        var strings = [
            PanelPresenter.searchPlaceholder, PanelPresenter.hint, PanelPresenter.emptyHint,
        ]

        let populated = PanelFixture.panel([
            PanelFixture.clip("a note", minutesAgo: 1, alias: "/note", category: "Work"),
            PanelFixture.clip("sk-live-abcdef123456", kind: .secret, minutesAgo: 2),
        ])
        // Empty in each of the ways it can be empty, since each writes its own sentences.
        let empties = [
            PanelFixture.panel([]),
            PanelFixture.panel(query: "nothing matches this"),
            PanelFixture.panel(filter: .links),
        ]

        for snapshot in [populated] + empties {
            let panel = PanelPresenter.present(snapshot)
            strings += [panel.searchPlaceholder, panel.hint]
            strings += panel.tabs.map(\.title)
            strings += [panel.emptyState?.title, panel.emptyState?.message].compactMap(\.self)
            strings += panel.filters.map(\.title)
            strings += panel.categories.map(\.title)
            for row in panel.rows {
                strings += [row.summary, row.when]
                strings += [row.alias, row.category].compactMap(\.self)
                strings += row.actions.map(\.title)
            }
        }
        return strings
    }

    /// Any of these in a sentence about the clipboard describes a product that does not
    /// exist. Over-promising in the user's favour is not a defence — it is what let the
    /// old wording stand.
    static let claimsOfElsewhere = [
        "synced", "syncs", "syncing", "sync ",
        "across devices", "other devices", "all your devices",
        "iCloud", "in the cloud", "uploaded", "backed up", "on our servers",
    ]

    @Test("nothing the panel says claims the clipboard leaves this Mac")
    func nothingClaimsSyncing() {
        for string in Self.everyPanelString() {
            let sentence = string.lowercased()
            for claim in Self.claimsOfElsewhere {
                #expect(
                    !sentence.contains(claim.lowercased()),
                    "“\(claim)” claims the clipboard goes elsewhere, in: \(string)")
            }
        }
    }

}
