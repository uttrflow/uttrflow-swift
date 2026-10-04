import SwiftUI
import UttrflowUX

/// The suggestion surface, drawn from ``SuggestionPresentation`` and nothing else.
struct SuggestionView: View {
    let presentation: SuggestionPresentation
    /// The size the current form wants, so the panel claims no more of the screen.
    var onDesiredSize: (CGSize) -> Void = { _ in }

    var body: some View {
        // No animation: a replaced suggestion is swapped whole, so the old text is never drawn beside the new one.
        CappedWidth(maximum: presentation.maximumWidth) { form.background(backing) }
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                onDesiredSize($0)
            }
            .frame(
                maxWidth: .infinity, maxHeight: .infinity,
                alignment: presentation.direction == .rightToLeft ? .topTrailing : .topLeading
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presentation.surfaceAccessibilityLabel)
    }

    @ViewBuilder private var form: some View {
        switch presentation.style {
        case .hidden:
            EmptyView()
        case .dot:
            dot
        case .ghost:
            ghost
        }
    }

    /// Draws a surface behind the ghost only where the field's colour is unknown, so the ghost has a background it was resolved for.
    @ViewBuilder private var backing: some View {
        if presentation.ink == .backed, presentation.style != .hidden {
            RoundedRectangle(cornerRadius: presentation.pointSize * 0.2)
                .fill(.background.opacity(SuggestionPresentation.backingOpacity))
        }
    }

    /// Returns the ghost's colour at a share of its strength: the field's text colour where known, else the primary one.
    private func ink(_ share: Double) -> Color {
        presentation.inkColor(at: share)
    }

    /// All that is left after the user presses escape.
    private var dot: some View {
        Circle()
            .fill(ink(presentation.opacity))
            .frame(
                width: SuggestionPresentation.dotDiameter,
                height: SuggestionPresentation.dotDiameter)
    }

    /// The continuation on the caret's own line, and the list of every candidate under it only once it is opened.
    private var ghost: some View {
        HStack {
            if presentation.direction == .rightToLeft { Spacer(minLength: 0) }
            ghostContent
            if presentation.direction == .leftToRight { Spacer(minLength: 0) }
        }
    }

    private var ghostContent: some View {
        VStack(alignment: presentation.direction == .rightToLeft ? .trailing : .leading, spacing: 0) {
            if let inline = presentation.inline { inlineLine(inline) }
            if presentation.isExpanded { list }
        }
        .environment(\.layoutDirection, presentation.direction == .rightToLeft ? .rightToLeft : .leftToRight)
    }

    /// What the accept key will add, finishing the user's line, and nothing else: the grey, or its underline, is the hint.
    private func inlineLine(_ row: SuggestionPresentation.Row) -> some View {
        SuggestionGhostLine(presentation: presentation, row: row)
            .foregroundStyle(ink(presentation.opacity))
    }

    /// Every candidate as a whole line, the one Tab takes at ghost strength and the rest dimmer, then the keys.
    private var list: some View {
        VStack(
            alignment: presentation.direction == .rightToLeft ? .trailing : .leading,
            spacing: presentation.pointSize * 0.2
        ) {
            ForEach(Array(presentation.list.enumerated()), id: \.offset) { _, row in
                SuggestionListRow(presentation: presentation, row: row)
            }
            footer
        }
        .padding(.top, presentation.pointSize * 0.35)
    }

    /// The keys that work the open list, in the dimmed style so they never compete with the candidates.
    private var footer: some View {
        Text(verbatim: presentation.footer)
            .lineLimit(1)
            .truncationMode(.tail)
            .font(presentation.font(at: presentation.pointSize * 0.82))
            .foregroundStyle(ink(presentation.unselectedListOpacity))
            .accessibilityHidden(true)
    }

    /// The selected row reads at full strength; unselected rows use their contrast-safe list opacity.
    private func rowOpacity(_ row: SuggestionPresentation.Row) -> Double {
        presentation.listOpacity(for: row)
    }
}

struct SuggestionListRow: View {
    let presentation: SuggestionPresentation
    let row: SuggestionPresentation.Row

    var body: some View {
        content
            .environment(
                \.layoutDirection,
                presentation.direction == .rightToLeft ? .rightToLeft : .leftToRight)
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: presentation.pointSize * 0.4) {
            Text(verbatim: SuggestionPresentation.listPrefix)
            Text(verbatim: row.candidate)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(presentation.font(at: presentation.pointSize))
        .fontWeight(row.isSelected ? .semibold : .regular)
        .foregroundStyle(presentation.inkColor(at: presentation.listOpacity(for: row)))
    }
}

/// The ghost on the caret's line, the one view both drawn and measured, so what fits is what is shown.
struct SuggestionGhostLine: View {
    let presentation: SuggestionPresentation
    let row: SuggestionPresentation.Row

    /// The ghost continuation, preceded by the typed characters struck through only when Tab would consume any.
    var body: some View {
        Text(text)
            .font(presentation.font(at: presentation.pointSize))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// The ghost in the field's style, with what Tab takes back struck through ahead of it.
    private var text: AttributedString {
        var text = AttributedString(row.ghost)
        // At full strength the grey no longer marks the offer, so a dotted underline does.
        if presentation.underlinesGhost { text.underlineStyle = Text.LineStyle(pattern: .dot) }
        guard row.isReplacement else { return text }
        var consumed = AttributedString(row.consumed)
        // The strike is the whole signal, so it takes the colour of the style around it.
        consumed.strikethroughStyle = .single
        return consumed + text
    }
}

extension SuggestionPresentation {
    /// Draws content at a share of the field's text colour or the backed surface's primary colour.
    func inkColor(at share: Double) -> Color {
        switch ink {
        case .field(let color):
            Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: share)
        case .backed:
            Color.primary.opacity(share)
        }
    }

    /// The field's own face where it names one, else the system face, monospaced where even the size is unknown.
    func font(at size: CGFloat) -> Font {
        var font: Font
        if let fontFamily {
            font = .custom(fontFamily, size: size)
        } else {
            font = .system(size: size, design: prefersMonospaced ? .monospaced : .default)
        }
        if isBold { font = font.weight(.bold) }
        if isItalic { font = font.italic() }
        return font
    }
}

/// Sizes its content at its own ideal width but never wider than the maximum, whatever the window around it offers.
struct CappedWidth: Layout {
    let maximum: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = cappedWidth(of: content)
        let measured = content.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: measured.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let content = subviews.first else { return }
        content.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: cappedWidth(of: content), height: nil))
    }

    /// The content's ideal width, cut to the maximum where there is one.
    private func cappedWidth(of content: LayoutSubview) -> CGFloat {
        let ideal = content.sizeThatFits(.unspecified).width
        guard let maximum else { return ideal }
        return min(ideal, maximum)
    }
}
