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
            lines
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

    /// The leader on the caret's own line, then any alternatives as grey lines directly below it.
    private var lines: some View {
        VStack(alignment: .leading, spacing: presentation.pointSize * 0.25) {
            ForEach(Array(presentation.rows.enumerated()), id: \.offset) { _, row in
                line(row)
            }
        }
    }

    private func line(_ row: SuggestionPresentation.Row) -> some View {
        HStack(spacing: presentation.pointSize * 0.35) {
            if row.showsMark { UttrflowMarkView(height: presentation.pointSize * 0.8) }
            offer(row)
            if row.isSelected { tabGlyph }
        }
        // The leader is drawn at the ghost's own strength; an unselected alternative is dimmer still.
        .foregroundStyle(.primary.opacity(rowOpacity(row)))
    }

    /// Full ghost strength for the row Tab would take, and half that for the ones it would not.
    private func rowOpacity(_ row: SuggestionPresentation.Row) -> Double {
        row.isSelected ? presentation.opacity : presentation.opacity * 0.55
    }

    /// The typed characters Tab consumes, struck through, and then the ones it puts in.
    private func offer(_ row: SuggestionPresentation.Row) -> some View {
        var consumed = AttributedString(row.consumed)
        // The strike is the whole signal, so it takes the colour of the style around it.
        consumed.strikethroughStyle = .single
        return Text(consumed + AttributedString(row.ghost))
            .font(.system(size: presentation.pointSize, design: fontDesign))
    }

    /// Monospaced where the field would not say what its own font is, so a terminal ghost still lines up.
    private var fontDesign: Font.Design {
        presentation.prefersMonospaced ? .monospaced : .default
    }

    /// A hairline marker, so the key that takes the suggestion is never a thing to guess.
    private var tabGlyph: some View {
        Text(verbatim: "⇥")
            .font(.system(size: presentation.pointSize * 0.72))
            .padding(.horizontal, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
