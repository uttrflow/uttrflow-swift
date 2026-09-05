// The main window's sidebar in its collapsed and expanded widths.

import UttrflowUX
import SwiftUI

import class Foundation.Bundle

extension AppVersion {
    /// What this bundle says it is, read in the app because `UttrflowUX` has no bundle of its own.
    static var ofThisBuild: AppVersion {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let short, !short.isEmpty else { return .unknown }
        return AppVersion(short: short, build: build ?? "")
    }
}

/// The navigation down the left of the window, an icon rail or the same rows with names beside them.
struct SidebarView: View {
    let presentation: SidebarPresentation
    /// Whether the names are showing. Remembered across launches by the window.
    var isExpanded: Bool = false
    var onSelect: (SidebarDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 1 : 3) {
            // Room for the traffic lights, which sit over the sidebar.
            Color.clear.frame(height: MainMetrics.titleBarInset)
            brand
                .padding(.bottom, isExpanded ? 6 : 10)
            ForEach(presentation.items) { item in
                row(item)
            }
            Spacer(minLength: 8)
            version
        }
        // Padding before the width, or the expanded sidebar is 220 points rather than 204.
        .padding(.horizontal, isExpanded ? 8 : 0)
        .frame(width: isExpanded ? MainMetrics.sidebarWidth : MainMetrics.iconRailWidth)
        .frame(maxHeight: .infinity)
        .background(Color.railGround)
    }

    /// The product's mark, bare and unaccented, with the name beside it only when the rows have names.
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

    /// Which build this is, at the foot; the build number rides along where there is room.
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
                // The number itself, which the rail cannot show; collapsed it is a dot.
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
        item.isSelected ? Color.dockActive : Color.railIcon
    }

    /// The count, as a dot rather than a number, for the width that has no room for one.
    @ViewBuilder private func dot(_ item: SidebarItem) -> some View {
        if item.badge != nil {
            Circle()
                .fill(Color.dockActive)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
                .padding(.trailing, 6)
        }
    }
}
