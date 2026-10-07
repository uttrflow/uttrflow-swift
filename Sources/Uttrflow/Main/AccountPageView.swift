// The Account page: an aurora banner with the person, the facts about them, and one button.

import UttrflowAccount
import UttrflowUX
import AppKit
import SwiftUI

/// Who is signed in, the four facts the app knows about them, and the way out or in.
struct AccountPageView: View {
    let presentation: AccountPagePresentation
    var onIntent: (MainIntent) -> Void

    var body: some View {
        if let empty = presentation.emptyState {
            VStack(spacing: 0) {
                MainEmptyStateView(state: empty, onIntent: onIntent)
                MainCalloutView(callout: presentation.callout)
            }
            .padding(.horizontal, 34)
            .padding(.top, 44)
            .padding(.bottom, 28)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let identity = presentation.identity {
                        AccountBanner(identity: identity)
                    }
                    if !presentation.facts.isEmpty {
                        AccountFactList(
                            facts: presentation.facts, providerID: presentation.identity?.providerID)
                    }
                    if let notice = presentation.notice {
                        MainCalloutView(callout: notice)
                    }
                    HStack(spacing: 10) {
                        if let action = presentation.action {
                            AccountActionButton(
                                action: action, help: presentation.actionHelp, onIntent: onIntent)
                        }
                        if let deletion = presentation.deletion {
                            AccountActionButton(
                                action: deletion, help: AccountPagePresenter.deletionHelp, onIntent: onIntent)
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 44)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// The wide aurora banner with the picture or initials, the name and the address.
struct AccountBanner: View {
    let identity: AccountIdentity

    /// The banner's fixed height.
    static let height: CGFloat = 180

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            AvatarView(identity: identity, size: 84, ring: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(identity.name)
                    .font(BrandFont.display(size: 30, weight: .semibold))
                    .tracking(-0.9)
                    .foregroundStyle(ProfilePalette.bannerInk)
                    .accessibilityAddTraits(.isHeader)
                if let email = identity.emailAddress {
                    Text(email)
                        .font(.system(size: 13.5))
                        .foregroundStyle(ProfilePalette.bannerSoft)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .frame(height: Self.height, alignment: .bottomLeading)
        .background { AccountAurora() }
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The banner's ground: the brand aurora, blurred once into a picture, over a dark that stays dark in the light appearance.
struct AccountAurora: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ProfilePalette.bannerGround
                if let picture = Self.picture(for: geometry.size) {
                    Image(nsImage: picture)
                        .resizable()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .opacity(0.75)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The last picture blurred and the banner size it was blurred for.
    @MainActor private static var blurred: (size: CGSize, image: NSImage)?

    /// The aurora for a banner of `size`, blurred the first time that size is asked for, so redraws never re-blur it.
    @MainActor static func picture(for size: CGSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        if let known = blurred, known.size == size { return known.image }
        let renderer = ImageRenderer(
            content: AngularGradient(
                colors: IslandPalette.aurora + IslandPalette.aurora.prefix(1),
                center: UnitPoint(x: 0.4, y: 0.6), startAngle: .degrees(120), endAngle: .degrees(480)
            )
            .frame(width: size.width * 1.8, height: size.height * 1.8)
            .blur(radius: 50)
            .frame(width: size.width, height: size.height))
        // A blur has no edges for a Retina pixel to sharpen.
        renderer.scale = 1
        guard let image = renderer.nsImage else { return nil }
        blurred = (size, image)
        return image
    }
}

/// The facts in one glass panel, a hairline between each.
struct AccountFactList: View {
    let facts: [AccountFact]
    /// Who signed this person in, which picks the sign-in row's glyph.
    let providerID: SignInProvider?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                AccountFactRow(fact: fact, providerID: providerID)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(ProfilePalette.glassRule)
                                .frame(height: 1)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(ProfilePalette.glassFill, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ProfilePalette.glassEdge, lineWidth: 1)
        }
    }
}

/// One fact: its glyph, its label and its value.
struct AccountFactRow: View {
    let fact: AccountFact
    let providerID: SignInProvider?

    var body: some View {
        HStack(spacing: 14) {
            AccountFactGlyph(kind: fact.kind, providerID: providerID)
                .frame(width: 16, height: 16)
            Text(fact.label)
                .font(.system(size: 13))
                .foregroundStyle(PagePalette.quiet)
                .frame(width: 140, alignment: .leading)
            Text(fact.value)
                .font(.system(size: 13.5))
                .foregroundStyle(PagePalette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

/// A fact's glyph; the sign-in row shows the provider, and Google's mark only when it was fetched.
struct AccountFactGlyph: View {
    let kind: AccountFact.Kind
    let providerID: SignInProvider?

    var body: some View {
        if kind == .signIn, providerID == .google,
            let mark = Bundle.module.image(forResource: "GoogleG")
        {
            Image(nsImage: mark)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 13))
                .foregroundStyle(PagePalette.quiet)
                .accessibilityHidden(true)
        }
    }

    /// A system symbol per fact; a provider's mark is never redrawn by approximation.
    var symbolName: String {
        switch kind {
        case .email: "envelope"
        case .since: "calendar"
        case .thisMac: "display"
        case .signIn:
            switch providerID {
            case .google: "globe"
            case .gitHub: "chevron.left.forwardslash.chevron.right"
            case .apple: "apple.logo"
            // Nobody signed this person in; the Mac is the only thing there is to draw.
            case nil: "laptopcomputer"
            }
        }
    }
}

/// Sign out in red, or Sign in in teal, at the foot of the page.
struct AccountActionButton: View {
    let action: MainAction
    let help: String?
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false

    /// The window's question host, when there is one; an action that asks first asks through it.
    @Environment(MainConfirmationCenter.self) private var confirmations: MainConfirmationCenter?

    var body: some View {
        Button {
            MainConfirmationCenter.press(action, in: confirmations, onIntent: onIntent)
        } label: {
            HStack(spacing: 8) {
                if let symbol = action.symbolName {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(wash.opacity(isHovered ? 1.5 : 1), in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(edge, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help ?? action.title)
    }

    private var ink: Color {
        action.isDestructive ? ProfilePalette.signOutInk : PagePalette.dictation
    }

    private var wash: Color {
        action.isDestructive ? ProfilePalette.signOutWash : PagePalette.dictation.opacity(0.12)
    }

    private var edge: Color {
        action.isDestructive ? ProfilePalette.signOutEdge : PagePalette.dictation.opacity(0.3)
    }
}

/// The Account page's own colours, each following the appearance.
enum ProfilePalette {
    private typealias R = BrandPalette.Redesign

    static let avatarInk = Color(rgb: R.avatarInk)
    /// The avatar disc, lilac at the top to teal at the foot.
    static let avatarDisc = LinearGradient(
        colors: [Color(nsColor: .orbit(R.avatarLilac)), Color(nsColor: .orbit(R.avatarTeal))],
        startPoint: UnitPoint(x: 0.25, y: 0.07), endPoint: UnitPoint(x: 0.75, y: 0.93))
    static let avatarRing = Color(nsColor: .orbit(R.avatarRing))
    static let bannerGround = Color(nsColor: .orbit(R.bannerGround))
    static let bannerInk = Color(nsColor: .orbit(R.bannerInk))
    static let bannerSoft = Color(nsColor: .orbit(R.bannerSoft))
    static let glassFill = Color(nsColor: .orbit(R.glassFill))
    static let glassEdge = Color(nsColor: .orbit(R.glassEdge))
    static let glassRule = Color(nsColor: .orbit(R.glassRule))
    static let signOutInk = Color(nsColor: .orbit(R.signOutInk))
    static let signOutWash = Color(nsColor: .orbit(R.signOutWash))
    static let signOutEdge = Color(nsColor: .orbit(R.signOutEdge))
}
