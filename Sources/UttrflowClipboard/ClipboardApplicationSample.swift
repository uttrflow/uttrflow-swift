/// The best available local app identity at a clipboard poll.
struct ClipboardApplicationSample: Equatable {
    let name: String?
    let bundleIdentifier: String?

    init(source: any ClipboardSource) {
        let application = source.frontmostApplication()
        name = application.name
        bundleIdentifier = application.bundleIdentifier
    }
}
