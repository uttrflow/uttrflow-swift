import UttrflowUX

enum PanelIntentRouting {
    static func forward(
        _ intent: PanelIntent,
        through sheet: PanelSheetPresentation?,
        to receive: (PanelIntent) -> Void
    ) {
        guard sheet == nil else { return }
        receive(intent)
    }
}
