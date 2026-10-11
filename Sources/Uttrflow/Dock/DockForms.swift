// The resting, hovered, listening and working forms of the dock.

import AppKit
import UttrflowCore
import UttrflowPipeline
import UttrflowUX
import SwiftUI

extension DockView {
    /// Three dots at the edge of the screen, drawn straight onto the desktop with no slab under them.
    var resting: some View {
        VStack(spacing: DockMetrics.gripDotSpacing) {
            ForEach(0..<DockMetrics.gripDotCount, id: \.self) { _ in
                Circle()
                    .fill(.primary.opacity(0.6))
                    .frame(width: DockMetrics.gripDotSize, height: DockMetrics.gripDotSize)
            }
        }
        .frame(width: DockMetrics.gripWidth, height: DockMetrics.gripHeight)
        // Lifts three points of ink off a pale wallpaper.
        .shadow(color: .black.opacity(0.38), radius: 1.5, y: 0.5)
        // Invisible but hoverable: a nine-point strip is hard to point at.
        .padding(DockMetrics.gripHitPadding)
    }

    /// Pointed at: the keycap hint beside the orb, which keeps the grip's side so it stays under the pointer.
    func hovered() -> some View {
        let orbLeads = model.anchor == .bottomLeft
        return HStack(spacing: 9) {
            if orbLeads { orb() }
            if let unheard = model.shortcutUnheard {
                Text(unheard)
                    .font(.system(size: DockMetrics.bodySize))
                    .frame(width: DockMetrics.unheardWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .glass(cornerRadius: DockMetrics.hintHeight / 2)
            } else {
                HStack(spacing: 8) {
                    Text(
                        String(
                            localized: "Dictate",
                            comment: "Dock hint beside the shortcut when the pointer is over the button")
                    )
                    .font(.system(size: DockMetrics.bodySize))
                    if !model.shortcut.isEmpty { keycap(model.shortcut) }
                }
                .fixedSize()
                .padding(.horizontal, 15)
                .frame(height: DockMetrics.hintHeight)
                .glass(cornerRadius: DockMetrics.hintHeight / 2)
            }
            if !orbLeads { orb() }
        }
        .padding(DockMetrics.gripHitPadding)
    }

    /// The idle orb wears the same three bars the meter is made of, at rest.
    func orb() -> some View {
        HStack(spacing: 2.5) {
            ForEach([6.0, 11.0, 7.0], id: \.self) { height in
                Capsule()
                    .fill(.primary.opacity(0.55))
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(width: DockMetrics.orbSize, height: DockMetrics.orbSize)
        .glass(cornerRadius: DockMetrics.orbSize / 2)
    }

    /// Listening: a live meter and a running clock, the clock on the anchored edge, and a line under it while the input is silent.
    func listening() -> some View {
        let clockLeads = model.anchor == .bottomLeft
        return VStack(alignment: clockLeads ? .leading : .trailing, spacing: 6) {
            HStack(spacing: 8) {
                if clockLeads { clock() }
                LevelMeterView(model: model, towardsLeading: clockLeads)
                if !clockLeads { clock() }
            }
            .padding(.horizontal, 12)
            .frame(height: DockMetrics.listeningHeight)
            .glass(cornerRadius: DockMetrics.listeningHeight / 2)
            if model.silence.isSilent {
                Text(InputSilence.line)
                    .font(.system(size: DockMetrics.bodySize))
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: DockMetrics.listeningHeight)
                    .glass(cornerRadius: DockMetrics.listeningHeight / 2)
            }
        }
        .padding(DockMetrics.gripHitPadding)
    }

    /// The time since the key went down, or the time left once the cap is near.
    func clock() -> some View {
        DockClock(model: model)
    }

    /// Working: a glass orb whose three bars keep settling for as long as there is work left to do.
    func working() -> some View {
        SettlingBars()
            .frame(width: DockMetrics.workingOrbSize, height: DockMetrics.workingOrbSize)
            .glass(cornerRadius: DockMetrics.workingOrbSize / 2)
            .padding(DockMetrics.gripHitPadding)
    }

    func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DockMetrics.footnoteSize, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(.primary.opacity(0.14), in: .rect(cornerRadius: 5))
    }
}
