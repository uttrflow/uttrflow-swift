import UttrflowClipboard

extension PanelPresenter {
    static func isMonospaced(_ kind: ClipKind) -> Bool {
        switch kind {
        case .code, .colour, .secret, .filePath: true
        case .text, .link, .image: false
        }
    }
}
