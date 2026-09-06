// How the verification tier retires a candidate, which is the corpus's supersession under another name.
public import UttrflowPredict

extension PredictStore: SupersessionRecording {
    /// Marks a candidate wrong for the verification tier, which has nowhere to report a failure to.
    public func recordSupersession(of text: String, by replacement: String, in surface: Surface) {
        try? supersede(text, with: replacement, in: surface)
    }

    /// Marks a refused candidate as its own successor, since nothing on this machine replaces it.
    public func recordRejection(of text: String, in surface: Surface) {
        try? supersede(text, with: text, in: surface)
    }
}
