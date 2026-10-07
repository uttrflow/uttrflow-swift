/// Compares text written by this module with the text a pasteboard exposes for pasting.
enum InsertionPasteboardReadback {
    /// Whether readback is identical, allowing its leading BOM to be omitted by the pasteboard.
    static func matches(_ readback: String?, for submitted: String) -> Bool {
        guard let readback else { return false }
        if readback.unicodeScalars.elementsEqual(submitted.unicodeScalars) { return true }
        var scalars = submitted.unicodeScalars
        guard scalars.first?.value == 0xFEFF else { return false }
        scalars.removeFirst()
        return readback.unicodeScalars.elementsEqual(scalars)
    }
}
