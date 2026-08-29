import AppKit
import Testing
import UttrflowClipboard

@testable import Uttrflow

/// Decoding a picture is the expensive thing the panel does, and a lazy list asks for its
/// rows again every time they come and go. What is worth testing is therefore not the
/// decode — that is ImageIO's job — but that it happens once.
@MainActor
@Suite("The pictures beside a clip")
struct PanelThumbnailsTests {
    private final class Counter { var files: [URL] = []; var sizes: [Int] = [] }

    /// A picture with real pixels behind it.
    ///
    /// `NSImage(size:)` has no representation at all, so it weighs nothing — which is
    /// fine for the tests about *how often* a file is read and useless for the ones about
    /// how much is being held. A cache bounded in bytes has to be given bytes.
    static func bitmap(_ edge: Int = PanelThumbnails.maxPixel) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: edge, pixelsHigh: edge, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        let image = NSImage(size: NSSize(width: edge, height: edge))
        if let rep { image.addRepresentation(rep) }
        return image
    }

    /// What one of those weighs, asked of the same function the cache uses so the two
    /// cannot disagree about the arithmetic.
    static let thumbnailBytes = PanelThumbnails.bytes(of: bitmap())

    private func thumbnails(
        _ answers: [URL: NSImage] = [:], budget: Int? = nil
    ) -> (PanelThumbnails, Counter) {
        let counter = Counter()
        let source = PanelThumbnailSource { file, maxPixel in
            counter.files.append(file)
            counter.sizes.append(maxPixel)
            return answers[file]
        }
        return (PanelThumbnails(source: source, budget: budget ?? PanelThumbnails.defaultBudget), counter)
    }

    func file(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/uttrflow-\(name).png")
    }

    private let file = URL(fileURLWithPath: "/tmp/uttrflow-shot.png")

    @Test("reads a picture once, however often the row is drawn")
    func decodesOnce() {
        let (thumbnails, counter) = thumbnails([file: NSImage(size: NSSize(width: 4, height: 4))])

        for _ in 0..<20 { _ = thumbnails.thumbnail(for: file) }

        #expect(counter.files == [file])
    }

    /// A clip whose file has been deleted since — the panel has a sentence for it, and
    /// the sentence should not cost a trip to the disk on every frame.
    @Test("remembers that a picture is gone")
    func remembersAMiss() {
        let (thumbnails, counter) = thumbnails()

        #expect(thumbnails.thumbnail(for: file) == nil)
        #expect(thumbnails.thumbnail(for: file) == nil)
        #expect(counter.files.count == 1)
    }

    /// Asked for at the size it is drawn rather than at the size it was taken: the point
    /// of the change was not to hold a twelve-megabyte screenshot to show a 34-point
    /// square of it.
    @Test("asks for the small version")
    func asksForAThumbnail() {
        let (thumbnails, counter) = thumbnails()

        _ = thumbnails.thumbnail(for: file)

        #expect(counter.sizes == [PanelThumbnails.maxPixel])
        #expect(PanelThumbnails.maxPixel <= 96, "a 34-point square on a Retina screen")
    }

    @Test("keeps different pictures apart")
    func separateFiles() {
        let other = URL(fileURLWithPath: "/tmp/uttrflow-other.png")
        let (thumbnails, counter) = thumbnails()

        _ = thumbnails.thumbnail(for: file)
        _ = thumbnails.thumbnail(for: other)

        #expect(counter.files == [file, other])
    }
}

/// What the cache costs when it is never emptied, and what it lets go of first.
///
/// The bound is bytes now rather than a count of entries, so these ask for room measured
/// in whole thumbnails — `pictures(2)` is "two will fit and a third will not", which is
/// the same sentence the old `capacity: 2` was making and no longer a guess about what
/// one of them weighs.
@MainActor
@Suite("What the picture cache lets go of")
struct PanelThumbnailsCapacityTests {
    private final class Counter { var files: [URL] = [] }

    private func thumbnails(room pictures: Int) -> (PanelThumbnails, Counter) {
        let counter = Counter()
        let source = PanelThumbnailSource { file, _ in
            counter.files.append(file)
            return PanelThumbnailsTests.bitmap()
        }
        return (
            PanelThumbnails(
                source: source, budget: PanelThumbnailsTests.thumbnailBytes * pictures),
            counter
        )
    }

    private func file(_ index: Int) -> URL { URL(fileURLWithPath: "/tmp/uttrflow-\(index).png") }

    @Test("forgets the least recently asked for once it is full")
    func evictsTheOldest() {
        let (thumbnails, counter) = thumbnails(room: 2)

        _ = thumbnails.thumbnail(for: file(1))
        _ = thumbnails.thumbnail(for: file(2))
        _ = thumbnails.thumbnail(for: file(3))  // pushes 1 out
        _ = thumbnails.thumbnail(for: file(2))  // still remembered
        _ = thumbnails.thumbnail(for: file(1))  // read again

        #expect(counter.files == [file(1), file(2), file(3), file(1)])
    }

    /// Recency is about being *asked for*, not about arriving: a picture at the top of the
    /// panel is looked at on every open, and it is the one that must not be evicted.
    @Test("asking again keeps a picture alive")
    func askingRefreshes() {
        let (thumbnails, counter) = thumbnails(room: 2)

        _ = thumbnails.thumbnail(for: file(1))
        _ = thumbnails.thumbnail(for: file(2))
        _ = thumbnails.thumbnail(for: file(1))  // 1 is now the newer of the two
        _ = thumbnails.thumbnail(for: file(3))  // so 2 goes, not 1
        _ = thumbnails.thumbnail(for: file(1))

        #expect(counter.files == [file(1), file(2), file(3)], "1 was never read twice")
    }

    @Test("holds what it is given, and no more")
    func staysUnderItsBudget() {
        let room = PanelThumbnailsTests.thumbnailBytes * 3
        let (thumbnails, _) = thumbnails(room: 3)

        for name in 1...20 { _ = thumbnails.thumbnail(for: file(name)) }

        #expect(thumbnails.bytesHeld <= room)
        #expect(thumbnails.bytesHeld > 0, "a cache that holds nothing is a decode per frame")
    }

    /// A budget of nothing would forget each answer before it could be used, turning the
    /// cache back into the decode-per-frame it exists to prevent.
    @Test("keeps at least one, whatever it is asked for")
    func neverKeepsNothing() {
        let (thumbnails, counter) = thumbnails(room: 0)

        _ = thumbnails.thumbnail(for: file(1))
        _ = thumbnails.thumbnail(for: file(1))

        #expect(counter.files == [file(1)])
    }

    /// The bound is the pictures' share of the clipboard's memory budget, and it is spent
    /// here because here is where the pixels actually are: the files never enter the
    /// process at full size.
    ///
    /// It used to be a count — two hundred — resting on "a thumbnail is about 18 KB". An
    /// estimate times a count is a budget that is right until a denser display or a wider
    /// row doubles each one, and then it is silently twice the budget.
    @Test("its bound is the picture tier of the clipboard budget, in bytes")
    func defaultBudget() {
        #expect(PanelThumbnails.defaultBudget == ClipboardBudget.standard.images.bytes)
        #expect(ClipboardBudget.standard.claimed <= ClipboardBudget.standard.ceiling)
    }

    /// The measurement the old count was guessing at, now that it can be taken.
    @Test("and a thumbnail weighs about what the budget assumed")
    func aThumbnailIsAboutEighteenKilobytes() {
        #expect(PanelThumbnailsTests.thumbnailBytes > 10_000)
        #expect(PanelThumbnailsTests.thumbnailBytes < 30_000)
    }

}
