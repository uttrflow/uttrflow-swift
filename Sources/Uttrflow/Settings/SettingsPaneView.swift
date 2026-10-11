// One Settings tab: banner, rejection, labelled cards of rows, the tidying example and the note.

import UttrflowUX
import UttrflowPermissions
import SwiftUI

/// One tab's worth of cards, written once for every tab; the differences are in the `SettingsPane`.
struct SettingsPaneView: View {
    let pane: SettingsPane
    let model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let banner = pane.banner {
                SettingsBannerView(banner: banner)
            }
            if let warning = model.globeKeyWarning {
                GlobeKeyWarningView(message: warning)
            }
            // The refusal sits above the cards, one place to look whichever control earned it.
            if let rejection = model.session.rejection {
                SettingsRejectionView(reason: rejection)
            }
            if let unavailability = pane.unavailability {
                Label(unavailability, systemImage: "info.circle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(PagePalette.faint)
            }
            if let empty = pane.emptySearch {
                Text(empty)
                    .font(.system(size: 13))
                    .foregroundStyle(PagePalette.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            }
            ForEach(pane.groups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    SettingsGroupView(group: group, model: model, paneUnavailability: pane.unavailability)
                    if let example = pane.example, example.groupID == group.id {
                        SettingsTidyExampleView(example: example)
                    }
                }
            }
            if let callout = pane.callout {
                SettingsCalloutView(callout: callout)
                    .padding(.top, -8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Warns that macOS will also act on the Globe key, with a direct route to Keyboard settings.
private struct GlobeKeyWarningView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Globe key also has a macOS action", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PagePalette.clipboard)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(PagePalette.text)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Keyboard Settings") {
                SystemSettingsOpener().open(.keyboard)
            }
            .buttonStyle(.link)
            .font(.system(size: 12, weight: .medium))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PagePalette.clipboard.opacity(0.1), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(PagePalette.clipboard.opacity(0.25), lineWidth: 1)
        )
    }
}

/// The small spaced capitals over a card.
struct SettingsSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.84)
            .foregroundStyle(PagePalette.faint)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A rounded film card, the one surface every group is drawn on.
struct SettingsCard<Content: View>: View {
    var isLit = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(SettingsPalette.ink(0.045), in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isLit ? PagePalette.dictation.opacity(0.3) : SettingsPalette.ink(0.08),
                        lineWidth: 1)
            )
    }
}

/// A card, and the small heading above it when it has one.
struct SettingsGroupView: View {
    let group: SettingsGroup
    let model: SettingsViewModel
    /// The reason the pane already gives once, which no row repeats.
    var paneUnavailability: String?

    /// Whether a shortcut in this card is listening, which lights the card's edge.
    private var isRecording: Bool {
        model.session.recorder.isRecording
            && group.rows.contains {
                if case .shortcut(let action, _) = $0.control {
                    return action == model.session.recorder.action
                }
                return false
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = group.title {
                SettingsSectionLabel(text: title)
            }
            SettingsCard(isLit: isRecording) {
                VStack(spacing: 0) {
                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                        // An inset row belongs to the row above it, so no line comes between them.
                        let ruled = index > 0 && row.style != .inset
                        SettingsRowView(row: row, model: model, paneUnavailability: paneUnavailability)
                            .overlay(alignment: .top) {
                                if ruled {
                                    Rectangle().fill(SettingsPalette.ink(0.07)).frame(height: 1)
                                }
                            }
                    }
                }
            }
        }
    }
}

/// A line in a card: its tile, what it says, and what it offers on the right.
struct SettingsRowView: View {
    let row: SettingsRow
    let model: SettingsViewModel
    /// The reason the pane already gives once, so this row keeps its own explanation instead.
    var paneUnavailability: String?

    var body: some View {
        Group {
            switch row.style {
            case .standard: standard
            case .inset: inset
            case .add: add
            }
        }
        .opacity(row.isEnabled ? 1 : 0.55)
        .disabled(!row.isEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var standard: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon = row.icon {
                SettingsIconTile(icon: icon)
            }
            words(labelSize: 13.5, explanationSize: 11.5)
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 58)
        .onDisappear { recordingRowGone() }
    }

    /// The card within the card, indented to line up with the words of the row above.
    private var inset: some View {
        HStack(alignment: .center, spacing: 14) {
            words(labelSize: 13, explanationSize: 11.5)
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(SettingsPalette.ink(0.035), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SettingsPalette.ink(0.06), lineWidth: 1)
        )
        .padding(.leading, 62)
        .padding(.trailing, 16)
        .padding(.bottom, 14)
    }

    /// The lone button at the foot of a list that adds to it.
    private var add: some View {
        HStack {
            if case .action(let title, let change) = row.control {
                Button {
                    model.apply(change)
                } label: {
                    Label(title, systemImage: "plus")
                        .labelStyle(SettingsLeadingIconLabelStyle())
                        .font(.system(size: 12.5))
                        .foregroundStyle(SettingsPalette.dictationInk)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func words(labelSize: CGFloat, explanationSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(row.label)
                    .font(.system(size: labelSize))
                    .foregroundStyle(SettingsPalette.ink(0.92))
                if row.badge == BetaFeature.label {
                    BetaBadge()
                } else if let badge = row.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(PagePalette.suggestion)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PagePalette.suggestion.opacity(0.18), in: .rect(cornerRadius: 5))
                }
            }
            // The reason a row is off replaces its explanation; two grey lines is a row nobody reads.
            if let unavailability = row.unavailability(besides: paneUnavailability) {
                secondary(unavailability, size: explanationSize)
            } else if recordsHere {
                secondary(SettingsShortcutRecorder.listeningHint, size: explanationSize)
            } else if let keyed = row.keyedExplanation {
                HStack(spacing: 6) {
                    secondary(keyed.before, size: explanationSize)
                    SettingsKeys(keys: keyed.keys, size: 20)
                    secondary(keyed.after, size: explanationSize)
                }
            } else if let explanation = row.explanation {
                secondary(explanation, size: explanationSize)
            }
        }
    }

    private func secondary(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(
                recordsHere && row.unavailability == nil
                    ? SettingsPalette.dictationInk : PagePalette.faint
            )
            .fixedSize(horizontal: false, vertical: true)
    }

    private var control: some View {
        SettingsControlView(
            control: row.control, isEnabled: row.isEnabled, label: row.label, model: model)
    }

    /// Whether this row's shortcut is the one listening, which its second line then says.
    private var recordsHere: Bool {
        guard case .shortcut(let action, _) = row.control else { return false }
        return model.session.recorder.isRecording && model.session.recorder.action == action
    }

    /// A search can hide the row that is listening, and a hidden row cannot be told the keys.
    private func recordingRowGone() {
        if recordsHere { model.cancelRecordingShortcut() }
    }
}

/// The same sentence as said and as written, side by side with an arrow between.
struct SettingsTidyExampleView: View {
    let example: SettingsTidyExample

    var body: some View {
        HStack(spacing: 10) {
            box(label: "You said", text: example.spoken, isWritten: false)
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PagePalette.dictation)
            box(label: example.writtenLabel, text: example.written, isWritten: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func box(label: String, text: String, isWritten: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(isWritten ? SettingsPalette.dictationInk : PagePalette.faint)
            Text(text)
                .font(BrandFont.display(size: 14, weight: isWritten ? .medium : .regular))
                .foregroundStyle(isWritten ? PagePalette.text : SettingsPalette.ink(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            isWritten ? PagePalette.dictation.opacity(0.08) : SettingsPalette.ink(0.035),
            in: .rect(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isWritten ? PagePalette.dictation.opacity(0.3) : SettingsPalette.ink(0.07), lineWidth: 1)
        )
    }
}

/// The statement a tab can open with: the model AI suggestions is waiting on.
struct SettingsBannerView: View {
    let banner: SettingsBanner

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            SettingsIconTile(icon: .symbol(banner.symbolName, .suggestion))
            VStack(alignment: .leading, spacing: 3) {
                Text(banner.title)
                    .font(BrandFont.display(size: 15, weight: .semibold))
                Text(banner.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsPalette.ink(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.ink(0.045), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(PagePalette.suggestion.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The tinted note at the foot of a pane.
struct SettingsCalloutView: View {
    let callout: SettingsCallout

    var body: some View {
        let tint = SettingsPalette.tint(callout.tint)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: callout.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(callout.message)
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(SettingsPalette.ink(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Why the last change did not happen.
struct SettingsRejectionView: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(PagePalette.clipboard)
            Text(reason)
                .font(.system(size: 12))
                .foregroundStyle(PagePalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PagePalette.clipboard.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PagePalette.clipboard.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
