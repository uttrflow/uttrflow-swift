import AppKit
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Panel auxiliary rendering")
struct PanelAuxiliaryRenderingTests {
    private func image(_ view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view.frame(width: 420, height: 180))
        renderer.scale = 1
        let picture = try #require(renderer.cgImage)
        #expect(picture.width == 420)
        #expect(picture.height == 180)
        return try #require(NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:]))
    }

    @Test("empty-state guidance changes visibly as recovery actions become available")
    func emptyActionsAreVisible() throws {
        let state = MainEmptyState(
            symbolName: "doc.on.clipboard", title: "Synthetic empty state",
            message: "Synthetic guidance wraps within the available panel width.")
        let action = PanelAction(
            title: "Synthetic recovery", symbolName: "magnifyingglass", intent: .keepQuery("synthetic"))
        var drawings: [Data] = []
        for (clear, recovery) in [(false, false), (true, false), (false, true), (true, true)] {
            drawings.append(
                try image(
                    PanelEmptyStateView(
                        state: state, showsClearSearch: clear, emptyAction: recovery ? action : nil,
                        onClearSearch: {}, onIntent: { _ in })))
        }
        #expect(Set(drawings).count == 4)
    }

    @Test("the application scope distinguishes everywhere from a confined synthetic draft")
    func scopesHaveDistinctDrawings() throws {
        let everywhere = try image(
            ApplicationScopeRow(
                line: ApplicationScopeLine(applications: []), applications: .constant([])))
        let confined = try image(
            ApplicationScopeRow(
                line: ApplicationScopeLine(applications: ["com.example.synthetic-editor"]),
                applications: .constant(["com.example.synthetic-editor"])))
        #expect(everywhere != confined)
    }
}
