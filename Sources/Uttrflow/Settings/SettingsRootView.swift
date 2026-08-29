import UttrflowUX
import SwiftUI

/// The Settings window: a sidebar, and the tab it has selected.
///
/// The view has no opinion about what a tab contains, which tabs exist, or whether a
/// control can be touched. All of that arrives as a ``SettingsWindowPresentation``, so
/// a fifth tab needs no change here at all.
struct SettingsRootView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        let presentation = model.session.presentation
        HStack(spacing: 0) {
            rail(presentation)
            VStack(alignment: .leading, spacing: 0) {
                Text(presentation.pane.title)
                    .font(.system(size: SettingsMetrics.paneTitleSize, weight: .bold))
                    .kerning(-0.3)
                    .padding(.top, SettingsMetrics.titleBarInset + 16)
                    .padding(.horizontal, SettingsMetrics.paneHorizontalPadding)
                    .padding(.bottom, 14)
                SettingsPaneView(pane: presentation.pane, model: model)
            }
        }
        .frame(
            minWidth: SettingsMetrics.windowWidth, minHeight: SettingsMetrics.windowHeight,
            alignment: .topLeading
        )
        // The same palette as the main window: this is the same app, and a settings
        // window drawn on the system's greys beside a window drawn on the design's
        // reads as somebody else's dialogue.
        .background(Color.mainBackground)
        .foregroundStyle(Color.mainText, Color.mainMuted, Color.mainDim)
        .tint(Color.dockAccent)
    }

    /// The four sections, down the left, on the accent.
    ///
    /// This was a strip of tabs across the top, and before that a plain sidebar. The
    /// tabs were the right answer while this window was drawn on the system's greys: a
    /// hundred and eighty-eight points of neutral rail to name four things is a poor
    /// trade. The rail earns its width now that it is the same rail first-run wears —
    /// it carries the identity, which the strip could only ever have tinted, and the two
    /// windows stop looking like two applications.
    private func rail(_ presentation: SettingsWindowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                UttrflowMarkView(height: 19)
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .kerning(-0.2)
            }
            .foregroundStyle(.white)
            .padding(.leading, 10)
            .padding(.bottom, 26)

            ForEach(presentation.tabs) { item in
                tab(item, isSelected: item.tab == presentation.selected)
            }
            Spacer(minLength: 12)
            if let identity = model.identity {
                account(identity)
            }
        }
        .padding(.top, SettingsMetrics.railTopInset)
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
        .frame(width: SettingsMetrics.railWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(RailGround())
    }

    /// Who this window is about, at the foot of the rail.
    ///
    /// Not a control: pressing it does nothing, and it deliberately offers nothing to
    /// press. Everything an account can be *done to* — signing out, changing the name,
    /// forgetting a device — is on the Account page in the main window, and a second
    /// place to do half of it is how the two come to disagree. This is here to answer
    /// the question a settings window should not make somebody leave to ask: whose
    /// settings are these?
    private func account(_ identity: AccountIdentity) -> some View {
        HStack(spacing: 9) {
            AvatarView(identity: identity, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(identity.provider)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signed in as \(identity.name), with \(identity.provider)")
    }

    private func tab(_ item: SettingsTabItem, isSelected: Bool) -> some View {
        Button {
            model.session.tab = item.tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.56))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                isSelected ? Color.white.opacity(0.10) : .clear,
                in: .rect(cornerRadius: 9)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

enum SettingsMetrics {
    /// Wider by the rail, so the pane keeps the width it had when the tabs were on top.
    static let windowWidth: CGFloat = 972
    static let windowHeight: CGFloat = 620
    static let railWidth: CGFloat = 212
    /// The room the traffic lights need above the mark.
    static let railTopInset: CGFloat = 52
    /// The room the traffic lights need above the pane's own title.
    static let titleBarInset: CGFloat = 30
    static let paneTitleSize: CGFloat = 20
    static let paneHorizontalPadding: CGFloat = 26
    static let paneVerticalPadding: CGFloat = 16
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 7
    static let rowMinimumHeight: CGFloat = 40
    static let titleSize: CGFloat = 17
    static let bodySize: CGFloat = 13
    static let calloutSize: CGFloat = 12
    static let subheadSize: CGFloat = 11
}
