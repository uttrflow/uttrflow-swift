public import UttrflowPredict

extension PredictStore: SupersessionRecording {
    /// Marks a candidate wrong for the verification tier, which has nowhere to report a failure to.
    public func recordSupersession(of text: String, by replacement: String, in surface: Surface) {
        try? supersede(text, with: replacement, in: surface)
    }
}
