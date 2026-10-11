import SwiftUI
import UttrflowUX

struct PanelEmptyStateView: View {
    let state: MainEmptyState
    let showsClearSearch: Bool
    let emptyAction: PanelAction?
    let onClearSearch: () -> Void
    let onIntent: (PanelIntent) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: state.symbolName)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.panelLabelDim)
                .accessibilityHidden(true)
            Text(state.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelLabelSoft)
            Text(state.message)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.panelLabelDim)
                .multilineTextAlignment(.center)
            if showsClearSearch {
                let title = String(
                    localized: "Clear search · Esc", comment: "Clear search action; Esc shortcut.")
                Button(title, action: onClearSearch)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.panelAccentBright)
                    .padding(.top, 2)
                    .accessibilityLabel(title)
            }
            if let action = emptyAction {
                Button(action.title) { onIntent(action.intent) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.panelAccentBright)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 40)
    }
}
