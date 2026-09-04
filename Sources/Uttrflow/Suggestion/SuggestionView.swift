import SwiftUI
import UttrflowUX

/// The suggestion surface, drawn from ``SuggestionPresentation`` and nothing else.
struct SuggestionView: View {
    let presentation: SuggestionPresentation
    /// The size the current form wants, so the panel claims no more of the screen.
    var onDesiredSize: (CGSize) -> Void = { _ in }

    var body: some View {
        form
            .fixedSize()
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                onDesiredSize($0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Nil under Reduce Motion, which is the whole of honouring it here.
            .animation(
                presentation.animates ? .easeOut(duration: 0.12) : nil, value: presentation
            )
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

    /// All that is left after the user presses escape.
    private var dot: some View {
        Circle()
            .fill(.primary.opacity(SuggestionPresentation.ghostOpacity))
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
            .foregroundStyle(.primary.opacity(presentation.opacity))
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
        }
        .font(font(at: presentation.pointSize))
        .foregroundStyle(.primary.opacity(rowOpacity(row)))
    }

    /// The keys that work the open list, in the dimmed style so they never compete with the candidates.
    private var footer: some View {
        Text(verbatim: presentation.footer)
            .font(font(at: presentation.pointSize * 0.82))
            .foregroundStyle(.primary.opacity(presentation.opacity * SuggestionPresentation.dimmedShare))
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
