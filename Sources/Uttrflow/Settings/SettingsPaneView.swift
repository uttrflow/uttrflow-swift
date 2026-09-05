// One Settings tab: banner, rejection, groups, rows and callout.

import UttrflowUX
import SwiftUI

/// One tab's worth of screen, written once for all four tabs; the differences are in the `SettingsPane`.
struct SettingsPaneView: View {
    let pane: SettingsPane
    let model: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // No title here: the window draws it once above the scroll view, so it stays put.
                if let banner = pane.banner {
                    SettingsBannerView(banner: banner)
                }

                // The refusal sits above the cards, one place to look whichever control earned it.
                if let rejection = model.session.rejection {
                    SettingsRejectionView(reason: rejection)
                }

                ForEach(pane.groups) { group in
                    SettingsGroupView(group: group, model: model)
                }

                if let callout = pane.callout {
                    SettingsCalloutView(callout: callout)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.paneHorizontalPadding)
            .padding(.vertical, SettingsMetrics.paneVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(
            asked?.confirmation?.title ?? "",
            isPresented: Binding(
                get: { model.session.pendingRemoval != nil },
                set: { isPresented in if !isPresented { model.dismissRemoval() } })
        ) {
            if let asked, let confirmation = asked.confirmation {
                // Cancel first and given Return, so a destructive button is never the default.
                Button(confirmation.cancelTitle, role: .cancel) { model.dismissRemoval() }
                    .keyboardShortcut(.defaultAction)
                Button(confirmation.confirmTitle, role: .destructive) { model.confirm(asked) }
            }
        } message: {
            Text(asked?.confirmation?.message ?? "")
        }
    }

    /// What is being asked, if anything; the session knows which button was pressed.
    private var asked: SettingsRemoval? { model.session.pendingRemoval }
}

/// A card, and the small heading above it when it has one.
struct SettingsGroupView: View {
    let group: SettingsGroup
    let model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title = group.title {
                Text(title.uppercased())
                    .font(.system(size: SettingsMetrics.subheadSize, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Color.mainDim)
            }
            VStack(spacing: 0) {
                MainDividedRows(rows: group.rows) { SettingsRowView(row: $0, model: model) }
            }
            .overlay(alignment: .top) { MainDivider() }
            .overlay(alignment: .bottom) { MainDivider() }
        }
    }
}

/// A line in a card: what it says on the left, what it offers on the right.
struct SettingsRowView: View {
    let row: SettingsRow
    let model: SettingsViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.system(size: SettingsMetrics.bodySize))
                // The reason a row is off replaces its explanation; two grey lines is a row nobody reads.
                if let secondary = row.unavailability ?? row.explanation {
                    Text(secondary)
                        .font(.system(size: SettingsMetrics.subheadSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            SettingsControlView(
                control: row.control, isEnabled: row.isEnabled, label: row.label, model: model)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(minHeight: SettingsMetrics.rowMinimumHeight)
        .opacity(row.isEnabled ? 1 : 0.55)
        .disabled(!row.isEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// The statement a tab can open with.
struct SettingsBannerView: View {
    let banner: SettingsBanner

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: banner.symbolName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.dockSuccess)
            VStack(alignment: .leading, spacing: 3) {
                Text(banner.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(banner.message)
                    .font(.system(size: SettingsMetrics.subheadSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: SettingsMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The tinted note at the foot of a pane.
struct SettingsCalloutView: View {
    let callout: SettingsCallout

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: callout.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
            Text(callout.message)
                .font(.system(size: SettingsMetrics.subheadSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dockAccentWash, in: .rect(cornerRadius: SettingsMetrics.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Why the last change did not happen.
struct SettingsRejectionView: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.dockWarning)
            Text(reason)
                .font(.system(size: SettingsMetrics.calloutSize))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dockWarning.opacity(0.12), in: .rect(cornerRadius: SettingsMetrics.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
