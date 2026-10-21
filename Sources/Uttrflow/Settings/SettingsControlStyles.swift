// The switch, segmented control, pop-up, buttons, keycaps and chips drawn in the redesign's style.

import AppKit
import SwiftUI
import UttrflowUX

// MARK: - Switch

/// A switch, drawn to the design rather than to the system's grey.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(track(isOn: configuration.isOn))
                .frame(width: 40, height: 24)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            configuration.isOn ? .clear : SettingsPalette.ink(0.1), lineWidth: 1)
                )
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .padding(.horizontal, 2)
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                }
                .shadow(
                    color: configuration.isOn ? PagePalette.dictation.opacity(0.6) : .clear,
                    radius: 6
                )
                .animation(
                    MotionBudget.current().allowing(.snappy(duration: 0.18)), value: configuration.isOn
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func track(isOn: Bool) -> AnyShapeStyle {
        isOn
            ? AnyShapeStyle(
                LinearGradient(
                    colors: [PagePalette.dictation, SettingsPalette.dictationDeep],
                    startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(SettingsPalette.ink(0.16))
    }
}

// MARK: - Segmented

/// Two or three answers side by side with the chosen one filled; SwiftUI cannot write a `PickerStyle`.
struct SettingsSegmented: View {
    let options: [(id: String, title: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { option in
                let isSelected = option.id == selection
                Button {
                    selection = option.id
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? SettingsPalette.inverseInk : SettingsPalette.ink(0.65))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(
                            isSelected ? SettingsPalette.inverseFill : .clear, in: .rect(cornerRadius: 8)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(SettingsPalette.ink(0.06), in: .rect(cornerRadius: 10))
    }
}

// MARK: - Pop-up

/// A long list behind a control that looks like the others; a `Menu`, since a pop-up's chrome is fixed.
struct SettingsMenu: View {
    /// What the row says the menu is for; the menu hides its own title, so VoiceOver needs this.
    let label: String
    let options: [(id: String, title: String)]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { option in
                Button {
                    selection = option.id
                } label: {
                    if option.id == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.id == selection }?.title ?? selection)
                    .font(.system(size: 12.5))
                    .foregroundStyle(PagePalette.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PagePalette.faint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(SettingsPalette.ink(0.07), in: .rect(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(SettingsPalette.ink(0.12), lineWidth: 1)
            )
            .contentShape(.rect)
        }
        // `.button` with a plain style; `.borderlessButton` draws its own indicator and no background.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityValue(options.first { $0.id == selection }?.title ?? selection)
    }
}

// MARK: - Buttons

/// The quiet button beside a control: Edit, Check Now, Remove, and the red one that removes for good.
struct SettingsButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isDestructive ? SettingsPalette.dangerInk : PagePalette.text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(
                isDestructive ? SettingsPalette.danger.opacity(0.12) : SettingsPalette.ink(0.08),
                in: .rect(cornerRadius: 9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isDestructive ? SettingsPalette.danger.opacity(0.3) : SettingsPalette.ink(0.14),
                        lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(.rect)
    }
}

/// An icon and its words side by side, closer than the system's label puts them.
struct SettingsLeadingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11, weight: .medium))
            configuration.title
        }
    }
}

// MARK: - Keys

/// A key drawn as a key: lit from above, with a shadow under its lip.
struct SettingsKeycap: View {
    let key: String
    var size: CGFloat = 30

    var body: some View {
        Text(key)
            .font(.system(size: (size * 0.42).rounded(), weight: .medium))
            .foregroundStyle(PagePalette.text)
            .fixedSize()
            .padding(.horizontal, (size * 0.28).rounded())
            .frame(minWidth: size, minHeight: size)
            .background(
                RoundedRectangle(cornerRadius: (size * 0.27).rounded(), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SettingsPalette.ink(0.2), SettingsPalette.ink(0.06)],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 0, y: max(2, (size * 0.08).rounded()))
            )
            .overlay(
                RoundedRectangle(cornerRadius: (size * 0.27).rounded(), style: .continuous)
                    .strokeBorder(SettingsPalette.ink(0.12), lineWidth: 0.5)
            )
            .overlay(alignment: .top) {
                // The highlight along the top edge that makes it read as raised.
                RoundedRectangle(cornerRadius: (size * 0.27).rounded(), style: .continuous)
                    .stroke(SettingsPalette.ink(0.25), lineWidth: 1)
                    .mask(alignment: .top) { Rectangle().frame(height: 1.5) }
            }
    }
}

/// A row of keycaps.
struct SettingsKeys: View {
    let keys: [String]
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                SettingsKeycap(key: key, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

// MARK: - Chips

/// A removable pill: a language being listened for, with the × that stops it.
struct SettingsChipView: View {
    let title: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12.5))
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PagePalette.faint)
                        .frame(width: 14, height: 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop listening for \(title)")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, onRemove == nil ? 12 : 8)
        .frame(height: 30)
        .background(SettingsPalette.ink(0.08), in: .capsule)
        .overlay(Capsule().strokeBorder(SettingsPalette.ink(0.12), lineWidth: 1))
        .fixedSize()
    }
}

// MARK: - Status

/// A fact that is fine: a green dot and a word.
struct SettingsStatusView: View {
    let text: String
    var tone: Color = SettingsPalette.good

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tone).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12))
        }
        .foregroundStyle(tone)
        .fixedSize()
    }
}

// MARK: - Tiles

/// The tinted square at the left of a row.
struct SettingsIconTile: View {
    let icon: SettingsIcon
    var size: CGFloat = 32

    var body: some View {
        switch icon {
        case .symbol(let name, let tint):
            let colour = SettingsPalette.tint(tint)
            Image(systemName: name)
                .font(.system(size: size * 0.48, weight: .regular))
                .foregroundStyle(colour)
                .frame(width: size, height: size)
                .background(colour.opacity(0.18), in: .rect(cornerRadius: size * 0.28, style: .continuous))
                .accessibilityHidden(true)
        case .application(let bundleIdentifier, let name):
            SettingsApplicationIcon(bundleIdentifier: bundleIdentifier, name: name)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// An application's own icon, asked of the system once and remembered.
struct SettingsApplicationIcon: View {
    let bundleIdentifier: String
    let name: String

    var body: some View {
        let application = HistoryApplication(
            name: name, initial: name.first.map(String.init) ?? "", identifier: bundleIdentifier)
        if let image = ApplicationIcons.shared.icon(for: application) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(SettingsPalette.ink(0.08))
                .overlay(
                    Image(systemName: "app")
                        .font(.system(size: 13))
                        .foregroundStyle(PagePalette.faint))
        }
    }
}
