// The Account page: identity card and detail rows.

import UttrflowUX
import SwiftUI

/// Who is signed in, and what that does and does not mean.
struct AccountPageView: View {
    let presentation: AccountPagePresentation
    var onIntent: (MainIntent) -> Void

    var body: some View {
        if let empty = presentation.emptyState {
            VStack(spacing: 0) {
                MainEmptyStateView(state: empty, onIntent: onIntent)
                MainCalloutView(callout: presentation.callout)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let identity = presentation.identity {
                        AccountIdentityCard(identity: identity)
                    }
                    if let notice = presentation.notice {
                        MainCalloutView(callout: notice)
                    }
                    details
                    MainCalloutView(callout: presentation.callout)
                    if let footnote = presentation.footnote {
                        MainFootnote(text: footnote)
                    }
                }
            }
        }
    }

    private var details: some View {
        VStack(spacing: 0) {
            MainDividedRows(rows: presentation.details) {
                AccountDetailRow(detail: $0, onIntent: onIntent)
            }
        }
        .cardSurface()
    }
}

/// The name, the address and the provider.
struct AccountIdentityCard: View {
    let identity: AccountIdentity

    var body: some View {
        MainCard(padding: 15) {
            HStack(spacing: 13) {
                AvatarView(identity: identity, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.name)
                        .font(.system(size: MainMetrics.titleSize, weight: .semibold))
                    if let email = identity.emailAddress {
                        Text(email)
                            .font(.system(size: MainMetrics.calloutSize))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Image(systemName: symbolName)
                        .font(.system(size: 12))
                    Text(identity.provider)
                        .font(.system(size: MainMetrics.calloutSize))
                }
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 6))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A system symbol rather than a provider's mark, whose drawing rules an approximation would break.
    private var symbolName: String {
        switch identity.providerID {
        case .google: "globe"
        case .gitHub: "chevron.left.forwardslash.chevron.right"
        case .apple: "apple.logo"
        // Nobody signed this person in; the Mac is the only thing there is to draw.
        case nil: "laptopcomputer"
        }
    }
}

/// One line of the account card.
struct AccountDetailRow: View {
    let detail: AccountDetail
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.label)
                    .font(.system(size: MainMetrics.bodySize))
                if let explanation = detail.explanation {
                    Text(explanation)
                        .font(.system(size: MainMetrics.subheadSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value = detail.value {
                Text(value)
                    .font(.system(size: MainMetrics.calloutSize))
            }
            if let action = detail.action {
                MainActionButton(action: action, onIntent: onIntent)
            }
        }
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 9)
        .frame(minHeight: 36)
        .accessibilityElement(children: .contain)
    }
}
