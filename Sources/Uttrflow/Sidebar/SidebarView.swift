import UttrflowUX
import SwiftUI

import class Foundation.Bundle

extension AppVersion {
    /// What this bundle says it is.
    ///
    /// Read here, in the app, because `UttrflowUX` has no bundle of its own — asking
    /// `Bundle.main` from inside a module would answer with whatever host happened to be
    /// running it, which in a test is the test runner.
    ///
    /// Both keys or neither: `Scripts/bundle.sh` check 1 refuses a bundle missing either,
    /// so a build that reaches a user has them, and a build that somehow does not draws
    /// nothing rather than "unknown (unknown)".
    static var ofThisBuild: AppVersion {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let short, !short.isEmpty else { return .unknown }
        return AppVersion(short: short, build: build ?? "")
    }
}

/// The navigation down the left of the window, in one of its two widths.
///
/// Collapsed it is a rail of icons; expanded it is the same destinations with their names
/// beside them. Collapsed is the default and the one the window opens in, because the
/// eleven destinations never change and are learnt in a day, and the hundred and
/// twenty-eight points the rail saves buy the page beside it the width its content
/// actually needs — the figures fit on one line and a dictation stops wrapping at four
/// words.
///
/// Expanded is not a luxury, though, which is why it exists: a rail asks you to know
/// eleven glyphs, and until you do, a name is the only thing that says where a row leads.
/// Every icon carries its name as a tooltip and as its accessibility label in both
/// widths, so nothing is ever only available to somebody who has learnt the glyphs.
///
/// Drawn entirely from ``SidebarPresentation``: which row is lit and what its badge says
/// are decided in ``UttrflowUX``. This file knows only where things go.
struct SidebarView: View {
    let presentation: SidebarPresentation
    /// Whether the names are showing. Remembered across launches by the window.
    var isExpanded: Bool = false
    var onSelect: (SidebarDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 1 : 3) {
            // Room for the traffic lights, which sit over the sidebar because the title
            // bar is transparent.
            Color.clear.frame(height: MainMetrics.titleBarInset)
            brand
                .padding(.bottom, isExpanded ? 6 : 10)
            ForEach(presentation.items) { item in
                row(item)
            }
            Spacer(minLength: 8)
            version
        }
        // Padding before the width, not after it: a frame outside padding is the frame
        // plus the padding, which would make the expanded sidebar 220 points rather than
        // the 204 the design asks for.
        .padding(.horizontal, isExpanded ? 8 : 0)
        .frame(width: isExpanded ? MainMetrics.sidebarWidth : MainMetrics.iconRailWidth)
        .frame(maxHeight: .infinity)
        .background(Color.railGround)
    }

    /// The product's own mark, and the only place in the window it appears.
    ///
    /// Bare, not on a tile. The sidebar is already the app's own dark, so a tile here
    /// would be a tile inside a tile — the same reason the quick panel carries the
    /// monogram rather than the app icon. And no accent: the sidebar tints what is
    /// *selected*, so a coloured mark at the top of it would read as a twelfth
    /// destination.
    ///
    /// The name appears beside it only when the names appear beside the rows. A wordmark
    /// over a column of unlabelled glyphs is the one arrangement that reads as an
    /// oversight rather than a choice.
    private var brand: some View {
        HStack(spacing: 8) {
            UttrflowMarkView(height: 21)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
            if isExpanded {
                Text(presentation.productName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mainText)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
        .accessibilityHidden(true)
    }

    /// Which build this is, at the foot, in both widths.
    ///
    /// Here rather than on a page because the question it answers — "which version are
    /// you on?" — is asked of people who are looking at something going wrong, and an
    /// answer they have to go and find is an answer half of them will guess at. It is the
    /// dimmest text in the window: always available, never competing with a destination.
    ///
    /// The build number rides along where there is room for it. Two builds of one version
    /// are exactly what a tester runs while something is being fixed, and "0.2.0" alone
    /// cannot tell them apart — the updater compares that number rather than the one
    /// people say out loud.
    @ViewBuilder private var version: some View {
        if presentation.version.isKnown {
            Text(isExpanded ? presentation.version.full : presentation.version.short)
                .font(.system(size: isExpanded ? 10.5 : 9))
                .monospacedDigit()
                .foregroundStyle(Color.mainDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, isExpanded ? 10 : 4)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
                .accessibilityLabel("Version \(presentation.version.full)")
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Button {
            onSelect(item.destination)
        } label: {
            content(item)
                .foregroundStyle(tint(item))
                .background(
                    item.isSelected ? Color.railSelection : .clear,
                    in: .rect(cornerRadius: isExpanded ? 7 : 10)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityAddTraits(item.isSelected ? [.isSelected] : [])
        .accessibilityLabel(item.badge.map { "\(item.title), \($0) today" } ?? item.title)
    }

    @ViewBuilder private func content(_ item: SidebarItem) -> some View {
        if isExpanded {
            HStack(spacing: 9) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13))
                Spacer(minLength: 6)
                // The number itself, which the rail cannot show. Forty-four points
                // cannot carry "3" without shrinking it past reading, so collapsed it is
                // a dot — the same fact, said in the room available.
                if let badge = item.badge {
                    Text(badge)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(item.isSelected ? Color.mainText : Color.mainDim)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: 15, weight: .regular))
                .frame(width: 44, height: 36)
                .overlay(alignment: .topTrailing) { dot(item) }
                .frame(maxWidth: .infinity)
        }
    }

    private func tint(_ item: SidebarItem) -> Color {
        item.isSelected ? Color.dockSecondary : Color.railIcon
    }

    /// The count, as a dot rather than a number, for the width that has no room for one.
    @ViewBuilder private func dot(_ item: SidebarItem) -> some View {
        if item.badge != nil {
            Circle()
                .fill(Color.dockSecondary)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
                .padding(.trailing, 6)
        }
    }
}
