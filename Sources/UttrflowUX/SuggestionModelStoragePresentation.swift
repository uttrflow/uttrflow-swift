package import Foundation

extension DiagnosticsPresenter {
    package static func page(
        for snapshot: DiagnosticsSnapshot, suggestionModelBytesOnDisk bytes: Int64?,
        locale: Locale = .autoupdatingCurrent
    ) -> DiagnosticsPresentation {
        let page = page(for: snapshot, locale: locale)
        guard let bytes else { return page }
        let installed = bytes > 0
        let detail =
            installed
            ? "\(MainFormatting.bytes(bytes, locale: locale)) on this Mac"
            : "Not downloaded"
        let row = DiagnosticsRow(
            title: "Suggestion model", detail: detail, state: installed ? .good : .unknown,
            action: installed
                ? MainAction(title: "Remove", intent: .removeSuggestionModel, isDestructive: true)
                : nil)
        return DiagnosticsPresentation(
            summary: page.summary, models: page.models, system: page.system,
            latency: page.latency, latencyEmptyState: page.latencyEmptyState,
            reliability: page.reliability, decoding: page.decoding,
            speechModelLoads: page.speechModelLoads, arrivals: page.arrivals,
            engines: page.engines, cleanUp: page.cleanUp,
            vocabularyPrompt: page.vocabularyPrompt, qualityLayers: page.qualityLayers,
            permissions: page.permissions, availability: page.availability,
            storage: page.storage + [row], footnote: page.footnote,
            copyAction: page.copyAction)
    }
}
