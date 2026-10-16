// Tests that the shared Beta badge keeps its word whole on one line in a crowded row.

import AppKit
import SwiftUI
import Testing

@testable import Uttrflow

@MainActor
@Suite("Beta badge layout")
struct BetaBadgeLayoutTests {
    private struct SizeKey: PreferenceKey {
        static let defaultValue = CGSize.zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }

    /// The badge's laid-out size when the row around it has `rowWidth` points to give.
    private func badgeSize(rowWidth: CGFloat) -> CGSize {
        var measured = CGSize.zero
        let row = HStack(spacing: 3) {
            Text("Clipboard").font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            BetaBadge().background(
                GeometryReader { Color.clear.preference(key: SizeKey.self, value: $0.size) })
        }
        .frame(width: rowWidth, height: 40)
        .onPreferenceChange(SizeKey.self) { measured = $0 }
        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: rowWidth, height: 40)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        return measured
    }

    @Test("a crowded row leaves the badge as wide and as tall as in a roomy row")
    func crowdedRowKeepsBadgeWhole() {
        let roomy = badgeSize(rowWidth: 300)
        let crowded = badgeSize(rowWidth: 50)
        #expect(roomy.width > 0)
        #expect(crowded == roomy)
        // One line of 9pt text plus its padding stays under two lines' height.
        #expect(roomy.height < 20)
    }
}
