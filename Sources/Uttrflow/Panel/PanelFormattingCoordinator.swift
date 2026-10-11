// Runs the panel's formatter and prepares a faithful diff before publishing into the current request.
import OSLog
import UttrflowClipboard
import UttrflowCore
import UttrflowUX

@MainActor
struct PanelFormattingCoordinator {
    let formatter: any CodeFormatting
    let log: Logger

    struct Actions {
        let isCurrent: () -> Bool
        let finish: (PanelFormatEnding) -> Void
        let present: (PreparedFormattingSheet, String) -> Void

        func end(with ending: PanelFormatEnding) {
            guard isCurrent() else { return }
            finish(ending)
        }
    }

    func run(text: String, language: CodeLanguage, actions: Actions) async {
        guard let produced = await formatter.format(text, as: language) else {
            log.info("formatter produced nothing for \(language.rawValue, privacy: .public)")
            actions.end(with: .unreadable)
            return
        }
        // Guarded and compared off the main actor, because both walk the whole clip.
        let prepared = await Task.detached(priority: .utility) {
            Self.prepare(produced, from: text)
        }.value
        guard let prepared else {
            log.error("formatter output discarded: not faithful (\(language.rawValue, privacy: .public))")
            actions.end(with: .unfaithful)
            return
        }
        guard let prepared else {
            actions.end(with: .alreadyFormatted)
            return
        }
        // A panel closed, reopened, re-sheeted, edited or formatted again since is left alone.
        guard actions.isCurrent() else { return }
        actions.present(prepared, produced)
    }

    nonisolated private static func prepare(
        _ produced: String, from original: String
    ) -> PreparedFormattingSheet?? {
        guard FormatterGuard.isFaithful(produced, to: original) else { return .none }
        guard produced != original else { return .some(nil) }
        return .some(PreparedFormattingSheet(from: original, to: produced))
    }
}
