import UttrflowUX
import AppKit
import SwiftUI

/// Whoever is signed in, as a circle: their picture, or their initials.
///
/// Both, in that order, and the initials are not a placeholder. The picture is fetched
/// over a network that may be off, from a provider that may be slow, and for an account
/// that may simply not have one — three situations this draws identically, because the
/// answer to all three is the letters it already has. Nothing here spins, and nothing
/// here apologises: a face that has not arrived is not an error, and a circle that showed
/// a stock silhouette would tell somebody with two accounts less than "NB" does.
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
        // The name is beside it on every page that draws one, so the circle is decoration
        // to a screen reader however it is filled in.
        .accessibilityHidden(true)
    }
}
