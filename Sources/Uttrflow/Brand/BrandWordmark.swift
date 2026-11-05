// The product's name as a logo, drawn the same wherever it appears beside the mark.

import SwiftUI

/// "UttrFlow" with a heavy first half and a regular second half, so the two read apart at any size.
struct BrandWordmark: View {
    /// The point size of the letters.
    let size: CGFloat

    /// The tracking and the extra gap between the halves, each as a share of the size.
    static let trackingShare: CGFloat = -0.035
    static let gapShare: CGFloat = 0.02

    /// The OpenType weights of the two halves.
    static let firstWeight: CGFloat = 800
    static let secondWeight: CGFloat = 400

    var body: some View {
        // Tracking draws no space after the last letter, so the gap carries one step of it.
        HStack(alignment: .firstTextBaseline, spacing: size * (Self.gapShare + Self.trackingShare)) {
            half("Uttr", weight: Self.firstWeight)
            half("Flow", weight: Self.secondWeight)
        }
        .fixedSize()
    }

    private func half(_ text: String, weight: CGFloat) -> some View {
        Text(verbatim: text)
            .font(BrandFont.wordmark(size: size, weight: weight))
            .tracking(size * Self.trackingShare)
    }
}
