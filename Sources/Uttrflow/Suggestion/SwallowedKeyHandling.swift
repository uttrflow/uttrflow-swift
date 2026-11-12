import Foundation
import OSLog
import UttrflowCore
import UttrflowInput
import UttrflowPredict
import UttrflowPredictCapture

/// The keyboard tap a drawn suggestion arms: `KeyInterceptor` in the app, a fake in a test.
@MainActor
protocol SuggestionKeyTap: AnyObject {
    func arm(_ keys: ArmedKeys)
    func releaseHeldKeys()
    func start() throws(KeyInterceptorFailure)
    func stop()
}

extension KeyInterceptor: SuggestionKeyTap {}

/// What the session made of a swallowed key, with the line typed and the field read before it decided.
struct SwallowedKeyRoute {
    let action: SuggestionAction
    let typed: String
    let reading: FieldReading?
}

/// What carrying out a tap event does to the coordinator, which owns the session, the panel and the field.
@MainActor
struct SwallowedKeyEffects {
    var route: @MainActor (UttrflowCore.KeyStroke) -> SwallowedKeyRoute
    /// Takes the drawn offer down and cancels the model pass that would draw another, ahead of an insert.
    var withdraw: @MainActor () -> Void
    /// Writes an accepted line into the field, then tells the session how the write ended.
    var take:
        @MainActor (String, SwallowedKeyRoute, _ recordsAcceptance: Bool) async ->
            UttrflowPredict.AcceptanceOutcome
    var requestFreshRead: @MainActor () -> Void
    var redraw: @MainActor (SuggestionUpdate) -> Void
    var noteActivity: @MainActor () -> Void
    var isSessionEnabled: @MainActor () -> Bool
    var turnOffEverywhere: @MainActor () -> Void
    var hidePanel: @MainActor () -> Void
    /// Whether a rested tap may start again: the feature runs and secure keyboard entry is not holding it.
    var mayRestartTap: @MainActor () -> Bool
    /// The rest beginning (nil), or the restart's result.
    var tapRestChanged: @MainActor (Result<Void, any Error>?) -> Void
    var tapRestRestarting: @MainActor () -> Void
}

/// Carries out each event the key tap reports, in the order it reports them. See `Docs/predict-accept.md`.
@MainActor
final class SwallowedKeyHandling {
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    /// How long the tap rests after macOS disabled it twice, past the window in which disables count against it.
    static let tapRestSeconds = 90

    private let tap: any SuggestionKeyTap
    private let rest: TapRest
    private let restDelay: Duration
    /// Presses a refused key again in the focused application.
    private let giveBack: @MainActor (UttrflowCore.KeyStroke) -> Void
    private var watching: Task<Void, Never>?
    /// True while an accepted completion is being inserted, so the keys it posts wake no further turn.
    private(set) var isInserting = false

    init(
        tap: any SuggestionKeyTap, rest: TapRest, restDelay: Duration = .seconds(tapRestSeconds),
        giveBack: @escaping @MainActor (UttrflowCore.KeyStroke) -> Void = { KeyStrokeReturn.post($0) }
    ) {
        self.tap = tap
        self.rest = rest
        self.restDelay = restDelay
        self.giveBack = giveBack
    }

    /// Handles the events one at a time, each finished before the next begins, until `stopWatching()`.
    func watch(_ events: AsyncStream<InterceptedEvent>, effects: SwallowedKeyEffects) {
        watching?.cancel()
        watching = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await handle(event, effects: effects)
            }
        }
    }

    func stopWatching() {
        watching?.cancel()
        watching = nil
    }

    /// One event from the tap: the tap giving up, or a key whose meaning the session decides.
    func handle(_ event: InterceptedEvent, effects: SwallowedKeyEffects) async {
        switch event {
        case .stopped(let failure):
            Self.log.error("the tap stopped: \(String(describing: failure), privacy: .public)")
            restTap(effects)
        case .swallowed(let stroke):
            let route = effects.route(stroke)
            Self.log.debug(
                "SWALLOWED key=\(String(describing: stroke.key), privacy: .public) modifiers=\(stroke.modifiers.rawValue) decision=\(route.action.logName, privacy: .public)"
            )
            switch route.action {
            case .accept(let text), .acceptWord(let text):
                await accept(text, of: stroke, route: route, effects: effects)
            // The field-value observer wakes after the destination exposes its insertion; the activity ticker is the fallback.
            case .redraw(let update): effects.redraw(update)
            case .giveBack(let refused, let drawn):
                drawn.map(effects.redraw)
                giveBack(refused)
            }
            // The keys pressed since this one reach the application only now, after anything it inserted.
            tap.releaseHeldKeys()
            // ⌥⎋ turns the feature off everywhere; persist it so the switch agrees and a later enable rebuilds this.
            if !effects.isSessionEnabled() { effects.turnOffEverywhere() }
        }
    }

    private func accept(
        _ text: String, of stroke: UttrflowCore.KeyStroke, route: SwallowedKeyRoute,
        effects: SwallowedKeyEffects
    ) async {
        effects.withdraw()
        tap.arm([])
        // Held across the insert so the keys it posts are ignored on both the tap and the monitor.
        isInserting = true
        let returnedKey = await SuggestionTake.acceptKeyToReturnIfTakeFails(stroke) {
            await effects.take(text, route, route.action == .accept(text))
        } requestFreshRead: {
            effects.requestFreshRead()
        }
        isInserting = false
        // A field that is no longer the drawn line gets its key back, so Tab still does what Tab does there.
        if let returnedKey { giveBack(returnedKey) }
        effects.noteActivity()
    }

    /// Rests the tap and starts it again, since a disable is usually the system's doing and the feature need not die of it.
    private func restTap(_ effects: SwallowedKeyEffects) {
        effects.tapRestChanged(nil)
        tap.arm([])
        tap.stop()
        effects.hidePanel()
        rest.schedule(
            after: restDelay, shouldRestart: effects.mayRestartTap, willRestart: effects.tapRestRestarting
        ) { [weak self] in
            guard let self, effects.mayRestartTap() else { return }
            do {
                try tap.start()
                Self.log.error("the tap is back after resting \(self.restDelay.components.seconds)s")
                effects.tapRestChanged(.success(()))
            } catch {
                Self.log.error("the tap could not restart: \(SuggestionLog.failure(error), privacy: .public)")
                effects.tapRestChanged(.failure(error))
            }
        }
    }
}
