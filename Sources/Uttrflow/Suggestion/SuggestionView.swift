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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presentation.accessibilityLabel)
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
        switch presentation.ink {
        case .field(let color):
            Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: share)
        case .backed:
            Color.primary.opacity(share)
        }
    }

    /// All that is left after the user presses escape.
    private var dot: some View {
        Circle()
            .fill(ink(SuggestionPresentation.ghostOpacity))
            .frame(
                width: SuggestionPresentation.dotDiameter,
                height: SuggestionPresentation.dotDiameter)
    }

    /// The continuation on the caret's own line, and the list of every candidate under it only once it is opened.
    private var ghost: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let inline = presentation.inline { inlineLine(inline) }
            if presentation.isExpanded { list }
        }
    }

    /// What the accept key will add, finishing the user's line, and nothing else: the grey itself is the hint.
    private func inlineLine(_ row: SuggestionPresentation.Row) -> some View {
        offer(row)
            .foregroundStyle(ink(presentation.opacity))
    }

    /// Every candidate as a whole line, the one Tab takes at ghost strength and the rest dimmer, then the keys.
    private var list: some View {
        VStack(alignment: .leading, spacing: presentation.pointSize * 0.2) {
            ForEach(Array(presentation.list.enumerated()), id: \.offset) { _, row in
                listRow(row)
            }
            footer
        }
        .padding(.top, presentation.pointSize * 0.35)
    }

    private func listRow(_ row: SuggestionPresentation.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: presentation.pointSize * 0.4) {
            Text(verbatim: SuggestionPresentation.listPrefix)
            Text(verbatim: row.candidate)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(font(at: presentation.pointSize))
        .foregroundStyle(ink(rowOpacity(row)))
    }

    /// The keys that work the open list, in the dimmed style so they never compete with the candidates.
    private var footer: some View {
        Text(verbatim: presentation.footer)
            .lineLimit(1)
            .truncationMode(.tail)
            .font(font(at: presentation.pointSize * 0.82))
            .foregroundStyle(ink(presentation.opacity * SuggestionPresentation.dimmedShare))
            .accessibilityHidden(true)
    }

    /// Full ghost strength for the row Tab would take, and a dimmed share for the ones it would not.
    private func rowOpacity(_ row: SuggestionPresentation.Row) -> Double {
        row.isSelected ? presentation.opacity : presentation.opacity * SuggestionPresentation.dimmedShare
    }

    /// The ghost continuation, preceded by the typed characters struck through only when Tab would consume any.
    private func offer(_ row: SuggestionPresentation.Row) -> some View {
        var text = AttributedString(row.ghost)
        if row.isReplacement {
            var consumed = AttributedString(row.consumed)
            // The strike is the whole signal, so it takes the colour of the style around it.
            consumed.strikethroughStyle = .single
            text = consumed + text
        }
        return Text(text)
            .font(font(at: presentation.pointSize))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// The field's own face where it names one, else the system face, monospaced where even the size is unknown.
    private func font(at size: CGFloat) -> Font {
        if let family = presentation.fontFamily { return .custom(family, size: size) }
        return .system(size: size, design: fontDesign)
    }

    /// Monospaced where the field would not say what its own font is, so a terminal ghost still lines up.
    private var fontDesign: Font.Design {
        presentation.prefersMonospaced ? .monospaced : .default
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
