// The main window's sidebar: a floating dark island, as an icon rail or with names beside the icons.

import UttrflowUX
import AppKit
import SwiftUI

import class Foundation.Bundle
import struct Foundation.Data

extension AppVersion {
    /// What this bundle says it is, read in the app because `UttrflowUX` has no bundle of its own.
    static var ofThisBuild: AppVersion {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let short, !short.isEmpty else { return .unknown }
        return AppVersion(short: short, build: build ?? "")
    }
}

/// The navigation down the left of the window, floating on the window's ground and dark in both appearances.
struct SidebarView: View {
    let presentation: SidebarPresentation
    /// Who is signed in, for the card at the foot.
    let account: HomeAccount
    /// The account's picture, when the provider gave one.
    var picture: Data?
    /// Whether the names are showing. Remembered across launches by the window.
    var isExpanded: Bool = false
    /// The page on screen, which lights its row ahead of the presentation catching up; `nil` defers to the presentation.
    var selection: SidebarDestination?
    var onSelect: (SidebarDestination) -> Void
    var onAccount: () -> Void = {}
    var onToggle: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights, which sit over the island.
            Color.clear.frame(height: SidebarMetrics.topInset)
            header
                .padding(.bottom, isExpanded ? 22 : 16)
            rows(.main)
            heading(.yourWords)
            rows(.yourWords)
            Spacer(minLength: 12)
            rows(.footer)
            SidebarAccountCard(
                account: account, picture: picture, version: presentation.version,
                isSelected: selection.map { $0 == .page(.account) } ?? presentation.isAccountSelected,
                isExpanded: isExpanded,
                onOpen: onAccount
            )
            .padding(.top, 10)
        }
        .padding(.horizontal, isExpanded ? 12 : 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { SidebarIslandBackground() }
        .clipShape(.rect(cornerRadius: SidebarMetrics.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SidebarMetrics.radius, style: .continuous)
                .strokeBorder(IslandPalette.accent.opacity(0.18), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .padding([.leading, .vertical], SidebarMetrics.margin)
        .frame(width: isExpanded ? MainMetrics.sidebarWidth : MainMetrics.iconRailWidth)
        .frame(maxHeight: .infinity)
    }

    /// The mark and the product's name, with the control that shows or hides the names.
    @ViewBuilder private var header: some View {
        if isExpanded {
            HStack(spacing: 10) {
                brand
                Spacer(minLength: 4)
                toggle
            }
            .padding(.horizontal, 8)
        } else {
            VStack(spacing: 12) {
                UttrflowMarkView(height: 20)
                    .foregroundStyle(IslandPalette.ink)
                toggle
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            UttrflowMarkView(height: 20)
                .foregroundStyle(IslandPalette.ink)
            Text(presentation.productName.lowercased())
                .font(BrandFont.wordmark(size: 21, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(IslandPalette.ink)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.productName)
    }

    private var toggle: some View {
        Button(action: onToggle) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(IslandPalette.quiet)
                .frame(width: 26, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide Sidebar" : "Show Sidebar")
        .accessibilityLabel(isExpanded ? "Hide Sidebar" : "Show Sidebar")
    }

    /// The heading over a group, or a hairline in the rail, which has no room for words.
    @ViewBuilder private func heading(_ section: SidebarSection) -> some View {
        if let title = section.title {
            if isExpanded {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.05)
                    .foregroundStyle(IslandPalette.quiet)
                    .padding(.horizontal, 12)
                    .padding(.top, 22)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Rectangle()
                    .fill(IslandPalette.ink.opacity(0.1))
                    .frame(width: 24, height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Whether a row is lit: by the page on screen when it is known, by the presentation otherwise.
    static func isLit(_ item: SidebarItem, given selection: SidebarDestination?) -> Bool {
        selection.map { SidebarPresenter.isSelected(item.destination, given: $0) } ?? item.isSelected
    }

    private func rows(_ section: SidebarSection) -> some View {
        ForEach(presentation.items(in: section)) { item in
            SidebarRow(
                item: item,
                isSelected: Self.isLit(item, given: selection),
                isExpanded: isExpanded
            ) { onSelect(item.destination) }
        }
    }
}

/// The island's measurements.
enum SidebarMetrics {
    /// The gap that floats the island off the window's edges.
    static let margin: CGFloat = 10
    static let radius: CGFloat = 18
    /// From the island's top edge to the logo, clear of the traffic lights.
    static let topInset: CGFloat = 48
}

/// The island's ground with the aurora glowing up from its foot: soft radial washes, violet to teal, with no edge.
struct SidebarIslandBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let reach = max(proxy.size.width, 1) * 1.7
            ZStack {
                IslandPalette.ground
                glow(IslandPalette.aurora[0], at: UnitPoint(x: -0.05, y: 1.02), reach: reach, strength: 0.5)
                glow(
                    IslandPalette.aurora[1], at: UnitPoint(x: 0.3, y: 1.08), reach: reach * 0.8,
                    strength: 0.35)
                glow(
                    IslandPalette.aurora[2], at: UnitPoint(x: 0.7, y: 1.05), reach: reach * 0.75,
                    strength: 0.3)
                glow(
                    IslandPalette.aurora[3], at: UnitPoint(x: 1.0, y: 1.0), reach: reach * 0.6, strength: 0.22
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One wash, strongest at its centre and gone by `reach`, eased so it has no ring.
    private func glow(_ color: Color, at center: UnitPoint, reach: CGFloat, strength: Double) -> some View {
        RadialGradient(
            stops: [
                .init(color: color.opacity(strength), location: 0),
                .init(color: color.opacity(strength * 0.55), location: 0.35),
                .init(color: color.opacity(strength * 0.18), location: 0.7),
                .init(color: color.opacity(0), location: 1),
            ],
            center: center, startRadius: 0, endRadius: reach)
    }
}

/// One destination: icon and name, lit with a teal wash and a bar at its leading edge when selected.
struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let isExpanded: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            content
                .foregroundStyle(IslandPalette.ink.opacity(isSelected ? 1 : 0.72))
                .background { SidebarSelection(isSelected: isSelected, isHovered: isHovered) }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.title)
        .accessibilitySelection(isSelected)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder private var content: some View {
        if isExpanded {
            HStack(spacing: 12) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 6)
                if let badge = item.badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(IslandPalette.ink.opacity(0.1), in: .capsule)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: 15, weight: .regular))
                .frame(width: 44, height: 40)
                .overlay(alignment: .topTrailing) {
                    // The count, as an amber dot, for the width that has no room for a number.
                    if item.badge != nil {
                        Circle()
                            .fill(PagePalette.clipboard)
                            .frame(width: 6, height: 6)
                            .padding(.top, 8)
                            .padding(.trailing, 9)
                    }
                }
                .frame(maxWidth: .infinity)
        }
    }
}

/// The selected row's teal wash, edge and leading bar, or a faint wash under the pointer.
struct SidebarSelection: View {
    let isSelected: Bool
    var isHovered = false
    var cornerRadius: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if isSelected {
            shape
                .fill(
                    LinearGradient(
                        colors: [IslandPalette.accent.opacity(0.22), IslandPalette.accent.opacity(0.06)],
                        startPoint: .leading, endPoint: .trailing)
                )
                .overlay { shape.strokeBorder(IslandPalette.accent.opacity(0.25), lineWidth: 1) }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(IslandPalette.accent)
                        .frame(width: 3)
                        .padding(.vertical, 10)
                }
        } else {
            shape.fill(IslandPalette.ink.opacity(isHovered ? 0.05 : 0))
        }
    }
}

/// The person at the foot of the island: their picture or initials, their name and the version.
struct SidebarAccountCard: View {
    let account: HomeAccount
    let picture: Data?
    let version: AppVersion
    let isSelected: Bool
    let isExpanded: Bool
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            Group {
                if isExpanded {
                    HStack(spacing: 12) {
                        avatar(size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                            if version.isKnown {
                                Text(version.tag)
                                    .font(.system(size: 12))
                                    .monospacedDigit()
                                    .foregroundStyle(IslandPalette.quiet)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                } else {
                    avatar(size: 30)
                        .padding(7)
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(IslandPalette.ink)
            .background {
                // Lit exactly as a selected row is, so Profile reads as the current page.
                if isSelected {
                    SidebarSelection(isSelected: true, cornerRadius: 14)
                } else if !isExpanded {
                    // The rail shows the disc alone, with a faint wash under the pointer.
                    SidebarSelection(isSelected: false, isHovered: isHovered, cornerRadius: 14)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(IslandPalette.ink.opacity(isHovered ? 0.1 : 0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(IslandPalette.ink.opacity(0.08), lineWidth: 1)
                        }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(account.open.title)
        .accessibilitySelection(isSelected)
        .accessibilityLabel(spokenLabel)
    }

    /// The picture where there is one, the initials on the lilac-to-teal disc otherwise.
    @ViewBuilder private func avatar(size: CGFloat) -> some View {
        switch account {
        case .signedIn(let initials, _, _):
            SidebarAvatar(initials: initials, picture: picture, size: size)
        case .signedOut:
            Image(systemName: "person.crop.circle")
                .font(.system(size: size * 0.6, weight: .regular))
                .foregroundStyle(IslandPalette.ink.opacity(0.72))
                .frame(width: size, height: size)
        }
    }

    private var name: String {
        switch account {
        case .signedIn(_, let name, _): name
        case .signedOut(let open): open.title
        }
    }

    /// Names the account and the build, because initials cannot be spoken and the version is the bug reporter's fact.
    private var spokenLabel: String {
        let who =
            switch account {
            case .signedIn(_, let name, let open): "\(open.title), \(name)"
            case .signedOut(let open): open.title
            }
        return version.isKnown ? "\(who). Version \(version.tag)" : who
    }
}

extension View {
    /// Says selected, and takes the trait away again when it is not, so VoiceOver never keeps a stale one.
    func accessibilitySelection(_ isSelected: Bool) -> some View {
        accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
    }
}
