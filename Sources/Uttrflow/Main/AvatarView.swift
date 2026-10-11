// The signed-in person's picture or initials in a circle.

import UttrflowUX
import AppKit
import SwiftUI

/// Whoever is signed in, as a circle: their picture, or their initials on the lilac-to-teal disc.
struct AvatarView: View {
    let identity: AccountIdentity
    var size: CGFloat = 44
    /// The width of the faint ring drawn outside the circle; none by default.
    var ring: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    /// The picture decoded at the drawn size, or any size already decoded until it is.
    @State private var image: CGImage?

    init(identity: AccountIdentity, size: CGFloat = 44, ring: CGFloat = 0) {
        self.identity = identity
        self.size = size
        self.ring = ring
        _image = State(initialValue: identity.picture.flatMap(AccountPictures.anyCached(for:)))
    }

    var body: some View {
        Group {
            if identity.picture != nil, let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(identity.initials)
                    .font(BrandFont.display(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(ProfilePalette.avatarInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ProfilePalette.avatarDisc)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .task(id: Decode(picture: identity.picture, pixels: pixels)) {
            guard let picture = identity.picture else {
                image = nil
                return
            }
            image = AccountPictures.anyCached(for: picture)
            let decoded = await AccountPictures.image(for: picture, longestSide: pixels)
            guard !Task.isCancelled else { return }
            image = decoded ?? image
        }
        // Outside the frame, so the ring never moves what is laid out beside the circle.
        .background { Circle().fill(ProfilePalette.avatarRing).padding(-ring).opacity(ring > 0 ? 1 : 0) }
        // The name is beside it on every page, so the circle is decoration to a screen reader.
        .accessibilityHidden(true)
    }

    /// The circle's side in the display's pixels, which is the size the picture is decoded to.
    private var pixels: Int { Int((size * displayScale).rounded(.up)) }

    /// What a decode depends on, so a new picture or a new display decodes again.
    private struct Decode: Equatable {
        let picture: Data?
        let pixels: Int
    }
}
