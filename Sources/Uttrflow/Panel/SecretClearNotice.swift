// Adds the clearing delay to the app's own "Copied" notices, in the words the floating button uses.
import UttrflowUX

/// The clearing sentence appended to a notice's message; the wording is the floating button's report.
enum SecretClearNotice {
    /// The message with "It leaves the clipboard in 60 seconds" after it, or unchanged when clearing is off.
    static func appending(to message: String, after seconds: Int) -> String {
        let report = PanelPasteReport.after(.copied(.hiddenText(clearsAfterSeconds: seconds)))
        guard let sentence = report?.secondaryLine else { return message }
        return message.hasSuffix(".") ? "\(message) \(sentence)." : "\(message). \(sentence)"
    }
}

extension PanelNotice {
    /// The same notice, naming when the secret it reports leaves the clipboard.
    func namingSecretClear(after seconds: Int) -> PanelNotice {
        PanelNotice(
            symbolName: symbolName, message: SecretClearNotice.appending(to: message, after: seconds),
            action: action, announcementID: announcementID)
    }
}
