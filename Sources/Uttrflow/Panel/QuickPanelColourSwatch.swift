import SwiftUI
import UttrflowClipboard

struct QuickPanelColourSwatch: View {
    let colour: ClipColour

    var body: some View {
        Circle()
            .fill(Color(red: colour.red, green: colour.green, blue: colour.blue, opacity: colour.alpha))
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(Color.panelLine, lineWidth: 1))
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}
