import UttrflowUX
import SwiftUI

/// How much Uttrflow tidies and which languages it listens for, deciding it the settings window's way.
struct StylePageView: View {
    let presentation: StylePagePresentation
    var onIntent: (MainIntent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                ForEach(presentation.groups) { group in
                    VStack(alignment: .leading, spacing: 13) {
                        StyleGroupView(group: group.group, onIntent: onIntent)
                        if group.isFollowedByExample {
                            StyleExampleCard(example: presentation.example)
                        }
                    }
                }
                MainCalloutView(callout: presentation.callout)
            }
        }
    }
}

/// A card of rows, and the small heading above it.
struct StyleGroupView: View {
    let group: SettingsGroup
    var onIntent: (MainIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title = group.title {
                MainSectionLabel(text: title)
            }
            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { MainDivider() }
                    StyleRowView(row: row, onIntent: onIntent)
                }
            }
            .background(Color.mainCard, in: .rect(cornerRadius: MainMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MainMetrics.cardRadius)
                    .strokeBorder(Color.mainSeparator, lineWidth: 0.5))
        }
    }
}

/// One line: what it says on the left, what it offers on the right.
struct StyleRowView: View {
    let row: SettingsRow
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.system(size: MainMetrics.bodySize))
                if let explanation = row.explanation {
                    Text(explanation)
                        .font(.system(size: MainMetrics.subheadSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Why the row is off, in the row. A control drawn grey with no reason
                // beside it teaches the user the app is broken.
                if let unavailability = row.unavailability {
                    Text(unavailability)
                        .font(.system(size: MainMetrics.subheadSize))
                        .foregroundStyle(Color.dockWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            StyleControlView(control: row.control, onIntent: onIntent)
                .disabled(!row.isEnabled)
        }
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 9)
        .frame(minHeight: 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// The two controls this page can ask for; a presenter test refuses the presenter any other.
struct StyleControlView: View {
    let control: SettingsControl
    var onIntent: (MainIntent) -> Void

    var body: some View {
        switch control {
        case .segmented(let options, let selectedID):
            Picker("", selection: selection(options, selectedID)) {
                ForEach(options) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()

        case .tick(let isTicked, let change):
            Button {
                onIntent(.change(change))
            } label: {
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isTicked ? Color.dockAccent : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isTicked ? [.isSelected] : [])

        // Listed rather than caught by a `default`, so a new control on Style must be drawn here.
        case .toggle, .menu, .anchorPicker, .shortcut, .removal, .action, .text,
            .applicationSwitch:
            EmptyView()
        }
    }

    private func selection(_ options: [SettingsOption], _ selectedID: String) -> Binding<String> {
        Binding(
            get: { selectedID },
            set: { chosen in
                guard let option = options.first(where: { $0.id == chosen }) else { return }
                onIntent(.change(option.change))
            })
    }
}

/// The same sentence at each level, so the choice is shown rather than described.
struct StyleExampleCard: View {
    let example: StyleExample

    var body: some View {
        MainCard(padding: 13) {
            VStack(alignment: .leading, spacing: 6) {
                Text(example.heading.uppercased())
                    .font(.system(size: MainMetrics.footnoteSize, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
                line(example.spokenLabel, example.spoken, isQuiet: true)
                ForEach(example.outcomes) { outcome in
                    HStack(alignment: .top, spacing: 6) {
                        line(outcome.level.title, outcome.text, isQuiet: false)
                        if outcome.isCurrent {
                            MainPillView(pill: MainPill(text: "Current", tone: .accent))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func line(_ label: String, _ text: String, isQuiet: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(text)
                .foregroundStyle(isQuiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: MainMetrics.calloutSize))
        .accessibilityElement(children: .combine)
    }
}
