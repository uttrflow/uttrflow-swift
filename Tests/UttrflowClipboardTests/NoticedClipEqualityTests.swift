// Tests when two noticed clips are the same one, which includes the picture they carry.
import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Noticed clip equality")
struct NoticedClipEqualityTests {
    private let clip = Clip(text: "a picture", kind: .image, copiedAt: Date(timeIntervalSince1970: 0))
    private let bytes = Data([1, 2, 3, 4])

    @Test("the same clip with the same picture is equal")
    func samePicture() {
        #expect(
            NoticedClip(clip: clip, picture: (bytes, 2, 2)) == NoticedClip(clip: clip, picture: (bytes, 2, 2))
        )
    }

    @Test("pictures of different sizes are not equal, nor are different bytes, nor a picture and none")
    func differentPictures() {
        let base = NoticedClip(clip: clip, picture: (bytes, 2, 2))
        #expect(base != NoticedClip(clip: clip, picture: (bytes, 4, 1)))
        #expect(base != NoticedClip(clip: clip, picture: (bytes, 2, 3)))
        #expect(base != NoticedClip(clip: clip, picture: (Data([9]), 2, 2)))
        #expect(base != NoticedClip(clip: clip))
    }
}
