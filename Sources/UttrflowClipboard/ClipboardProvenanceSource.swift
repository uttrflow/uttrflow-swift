/// Sources that read writer and device attribution with the ordinary clipboard markers.
protocol ClipboardProvenanceSource: ClipboardSource {
    func clipboardProvenance() -> ClipboardProvenance
}
