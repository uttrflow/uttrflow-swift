// The sidebar's avatar disc and the account picture decoded for it.

import AppKit
import SwiftUI

import struct Foundation.Data

/// The account's picture, decoded off the main thread and small, over the initials until it is ready.
struct SidebarAvatar: View {
    let initials: String
    let picture: Data?
    let size: CGFloat

    @State private var image: CGImage?

    init(initials: String, picture: Data?, size: CGFloat) {
        self.initials = initials
        self.picture = picture
        self.size = size
        _image = State(initialValue: picture.flatMap { AccountPictures.cached(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(.circle)
            } else {
                Text(initials)
                    .font(BrandFont.display(size: size * 0.39, weight: .semibold))
                    .foregroundStyle(IslandPalette.avatarInk)
                    .frame(width: size, height: size)
                    .background(
                        LinearGradient(
                            colors: IslandPalette.avatar, startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        in: .circle)
            }
        }
        .task(id: picture) {
            guard let picture else {
                image = nil
                return
            }
            image = AccountPictures.cached(for: picture)
            let decoded = await AccountPictures.image(for: picture)
            guard !Task.isCancelled else { return }
            image = decoded ?? image
        }
    }
}

/// The account picture at each drawn size, decoded once per set of bytes and never on the main thread.
@MainActor
enum AccountPictures {
    /// The largest the sidebar avatar is drawn, in pixels on a Retina screen.
    static let pixels = 96
    /// The last picture decoded at each longest side, in pixels.
    private static var decoded: [Int: (data: Data, image: CGImage)] = [:]

    /// The decoded picture for these bytes at `longestSide` pixels, if it is the one already decoded.
    static func cached(for data: Data, longestSide: Int = pixels) -> CGImage? {
        decoded[longestSide].flatMap { $0.data == data ? $0.image : nil }
    }

    /// Any size already decoded for these bytes, the largest first, to draw while the right size decodes.
    static func anyCached(for data: Data) -> CGImage? {
        decoded.sorted { $0.key > $1.key }.lazy.compactMap { $0.value.data == data ? $0.value.image : nil }
            .first
    }

    /// The decoded picture for these bytes at `longestSide` pixels, decoding them away from the main thread when they are new.
    static func image(
        for data: Data,
        longestSide: Int = pixels,
        decode: @escaping @Sendable (Data, Int) async -> CGImage? = { data, longestSide in
            await Task.detached(priority: .userInitiated) {
                PictureDecoder.thumbnail(of: data, longestSide: longestSide)
            }.value
        }
    ) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        if let image = cached(for: data, longestSide: longestSide) { return image }
        let image = await decode(data, longestSide)
        guard !Task.isCancelled else { return nil }
        if let image { decoded[longestSide] = (data, image) }
        return image
    }
}
