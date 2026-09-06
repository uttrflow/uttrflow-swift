// The signed-in person's picture or initials in a circle.

import UttrflowUX
import AppKit
import SwiftUI

/// Whoever is signed in, as a circle: their picture, or their initials, which are not a placeholder.
struct AvatarView: View {
    let identity: AccountIdentity
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let picture = identity.picture, let image = NSImage(data: picture) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(identity.initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Color.dockAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dockAccent.opacity(0.14))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(Color.dockAccentTint, lineWidth: 1))
        // The name is beside it on every page, so the circle is decoration to a screen reader.
        .accessibilityHidden(true)
    }
}
