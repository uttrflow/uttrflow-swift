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
            lines.foregroundStyle(.primary.opacity(SuggestionPresentation.ghostOpacity))
        case .chip:
            chip
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

    /// Solid and bordered, because grey text on the user's own line is what the setting refuses.
    private var chip: some View {
        lines
            .padding(.horizontal, presentation.pointSize * 0.4)
            .padding(.vertical, presentation.pointSize * 0.25)
            .background(.background, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).strokeBorder(.primary, lineWidth: 1)
            }
    }

    /// The leader, then the alternatives under it.
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
