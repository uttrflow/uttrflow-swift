// The Home page: stage, figures, today's dictations and the clipboard demonstration.

import UttrflowUX
import SwiftUI

/// The page the window opens on: stage, figures, today's dictations, then the clipboard demonstration.
struct HomePageView: View {
    let presentation: HomePresentation
    var onIntent: (MainIntent) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OrbitStage(presentation: presentation, onIntent: onIntent)
                if !presentation.figures.isEmpty {
                    figures
                    MainDivider()
                }
                if let step = presentation.nextStep {
                    MainCard { MainEmptyStateView(state: step, onIntent: onIntent) }
                        .padding(MainMetrics.contentPadding)
                }
                today
                if let demonstration = presentation.demonstration {
                    ClipboardDemonstration(demonstration: demonstration)
                        .padding(.horizontal, MainMetrics.contentPadding)
                        .padding(.bottom, 18)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Today's dictations with the clipboard beside them; the list takes the width, the rail is fixed.
    private var today: some View {
        HStack(alignment: .top, spacing: 0) {
            recent
                .padding(.horizontal, MainMetrics.contentPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let demonstration = presentation.demonstration {
                Rectangle().fill(Color.mainSeparator).frame(width: 1)
                ClipboardRail(demonstration: demonstration, onIntent: onIntent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(width: 300, alignment: .leading)
            }
        }
    }

    /// The figures in one centred row under the stage, or a grid when the window is too narrow for the row.
    private var figures: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(presentation.figures.enumerated()), id: \.element.id) {
                    index, figure in
                    OrbitFigure(statistic: figure, tint: Self.tint(at: index))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 300), spacing: 12)],
                alignment: .leading, spacing: 12
            ) {
                ForEach(presentation.figures) { figure in
                    MainFigureTile(statistic: figure)
                }
            }
            .padding(.horizontal, MainMetrics.contentPadding)
            .padding(.vertical, 16)
        }
    }

    /// Bright teal, plain, deep teal, plain — the rhythm the row is drawn with.
    private static func tint(at index: Int) -> Color? {
        switch index % 4 {
        case 0: .dockActive
        case 2: .dockAccent
        default: nil
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                MainSectionLabel(text: presentation.recentTitle)
                Spacer(minLength: 0)
                if let seeAll = presentation.seeAll {
                    MainActionButton(action: seeAll, onIntent: onIntent)
                }
            }
            .padding(.bottom, 4)
            // Hairlines rather than a card: the list is the page's own content, not a panel dropped onto it.
            ForEach(presentation.recent) { row in
                MainDivider()
                HomeRowView(row: row, onIntent: onIntent)
            }
        }
    }
}

/// One dictation, at a glance.
struct HomeRowView: View {
    let row: HomeRow
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(row.when)
                .font(.system(size: MainMetrics.footnoteSize))
                .foregroundStyle(Color.mainDim)
                .monospacedDigit()
                .frame(width: 60, alignment: .leading)
                .padding(.top, 2)
            Text(row.text)
                .font(.system(size: MainMetrics.bodySize))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let application = row.application {
                MainApplicationChip(application: application)
                    .padding(.top, 1)
            }
            // Hidden rather than removed, so the row keeps its shape and a keyboard can still reach it.
            MainIconButton(action: row.open, onIntent: onIntent)
                .opacity(isHovered ? 1 : 0)
                .padding(.top, -2)
        }
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.mainHover : .clear)
        .onHover { isHovered = $0 }
        .rowActions([row.open], onIntent: onIntent)
    }
}
