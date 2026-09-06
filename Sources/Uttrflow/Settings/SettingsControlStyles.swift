// The switch, segmented control, pop-up and button drawn in the app's own style.

import AppKit
import SwiftUI

/// The controls this window draws in the app's own vocabulary; behaviour stays the platform's.

// MARK: - Switch

/// A switch, drawn to the design rather than to the system's grey.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(track(isOn: configuration.isOn))
                .frame(width: 38, height: 22)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            configuration.isOn ? .clear : Color.mainSeparator, lineWidth: 1)
                )
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? .white : Color.mainMuted)
                        .frame(width: 18, height: 18)
                        .padding(.horizontal, 2)
                        .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
                }
                .shadow(
                    color: configuration.isOn ? .dockAccent.opacity(0.40) : .clear,
                    radius: 8, y: 2
                )
                .animation(.snappy(duration: 0.18), value: configuration.isOn)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func track(isOn: Bool) -> AnyShapeStyle {
        isOn ? AnyShapeStyle(LinearGradient.accentFill) : AnyShapeStyle(Color.settingsControl)
    }
}

// MARK: - Segmented

/// Two or three answers side by side with the chosen one filled; SwiftUI cannot write a `PickerStyle`.
struct SettingsSegmented: View {
    let options: [(id: String, title: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.id) { option in
                let isSelected = option.id == selection
                Button {
                    selection = option.id
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : Color.mainMuted)
                        .padding(.horizontal, 13)
                        .frame(height: 24)
                        .background(
                            isSelected
                                ? AnyShapeStyle(LinearGradient.accentFill) : AnyShapeStyle(Color.clear),
                            in: .rect(cornerRadius: 6)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Color.settingsControl, in: .rect(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.mainSeparator, lineWidth: 1))
    }
}

// MARK: - Pop-up

/// A long list behind a control that looks like the others; a `Menu`, since a pop-up's chrome is fixed.
struct SettingsMenu: View {
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
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.mainText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.settingsAccentInk)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.settingsControl, in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.mainSeparator, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        // `.button` with a plain style; `.borderlessButton` draws its own indicator and no background.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Buttons

/// The quiet button beside a control: Change, Cancel, and the like.
struct SettingsButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isDestructive ? Color(nsColor: .systemRed) : Color.mainMuted)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Color.settingsControl, in: .rect(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isDestructive
                            ? Color(nsColor: .systemRed).opacity(0.35) : Color.mainSeparator,
                        lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(.rect)
    }
}

// MARK: - Colours

extension Color {
    /// The fill under a control on a card, one step lifted, so a switch does not read as a hole.
    static let settingsControl = Color(nsColor: .orbit(dark: 0x12_151C, light: 0xF1_F0F5))
    /// The accent as a mark rather than a fill, in a window that follows the system's appearance.
    static let settingsAccentInk = Color(nsColor: .orbit(dark: 0x5F_E0D3, light: 0x0E_6B64))
}
