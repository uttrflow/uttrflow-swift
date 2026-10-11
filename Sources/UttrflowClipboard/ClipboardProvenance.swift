import UttrflowCore

/// The attribution carried by the current pasteboard generation.
struct ClipboardProvenance: Sendable {
    static let remoteSource = "Another device"
    static let writerType = "org.nspasteboard.source"
    static let remoteType = "com.apple.is-remote-clipboard"

    let markers: PasteboardMarkers
    let writerBundleIdentifier: String?
    let isRemote: Bool

    private var normalizedWriterBundleIdentifier: String? {
        guard let writerBundleIdentifier else { return nil }
        let trimmed = writerBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    init(
        markers: PasteboardMarkers, writerBundleIdentifier: String? = nil, isRemote: Bool = false
    ) {
        self.markers = markers
        self.writerBundleIdentifier = writerBundleIdentifier
        self.isRemote = isRemote
    }

    init(types: [String], writerValue: String? = nil) {
        self.init(
            markers: PasteboardMarkers(types: types),
            writerBundleIdentifier: types.contains(Self.writerType) ? writerValue : nil,
            isRemote: types.contains(Self.remoteType))
    }

    static func reading(from source: any ClipboardSource) -> Self {
        if let source = source as? any ClipboardProvenanceSource {
            return source.clipboardProvenance()
        }
        return Self(markers: source.markers())
    }

    func excludesDeclaredWriter(from excludedApplications: Set<String>) -> Bool {
        guard let writerBundleIdentifier = normalizedWriterBundleIdentifier else { return false }
        return excludedApplications.contains(writerBundleIdentifier.lowercased())
    }

    func excludesFrontmostApplication(
        from excludedApplications: Set<String>, previous: ClipboardApplicationSample,
        current: ClipboardApplicationSample, changed: Bool, isUnknown: Bool
    ) -> Bool {
        guard normalizedWriterBundleIdentifier == nil, !isRemote else { return false }
        if changed {
            return [previous.bundleIdentifier, current.bundleIdentifier].contains {
                guard let identifier = $0 else { return false }
                return excludedApplications.contains(identifier.lowercased())
            }
        }
        guard !isUnknown, let identifier = current.bundleIdentifier else { return false }
        return excludedApplications.contains(identifier.lowercased())
    }

    func sourceName(frontmostName: String?, isUnknown: Bool) -> String? {
        if isRemote { return Self.remoteSource }
        if let normalizedWriterBundleIdentifier { return normalizedWriterBundleIdentifier }
        return isUnknown ? nil : frontmostName
    }
}
