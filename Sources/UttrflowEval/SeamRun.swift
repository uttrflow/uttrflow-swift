// One run of the seam probe: each clip's seam artefacts, kept so a later run may not exceed them.
public import Foundation

/// Each clip's seam artefacts, summed over its seams, as one run of the seam probe measured them.
public struct SeamRun: Sendable, Equatable, Codable {
    /// The artefacts by clip id.
    public private(set) var clips: [String: SeamTally]

    public init(clips: [String: SeamTally] = [:]) { self.clips = clips }

    /// Records one clip's seams, replacing an earlier record of the same clip.
    public mutating func record(_ score: SeamScore, for clip: String) { clips[clip] = score.total }

    /// Every clip summed: the score one build of the app earns.
    public var total: SeamTally { clips.values.reduce(SeamTally(), +) }

    /// One line per clip and kind that counts more than in `baseline`; a clip the baseline lacks is held at zero.
    public func rises(over baseline: Self) -> [String] {
        clips.keys.sorted().flatMap { id in
            let now = clips[id] ?? SeamTally()
            let before = (baseline.clips[id] ?? SeamTally()).kinds
            return zip(now.kinds, before).compactMap { measured, recorded in
                measured.count > recorded.count
                    ? "\(id): \(measured.name) \(recorded.count) -> \(measured.count)" : nil
            }
        }
    }

    public func write(to url: URL) throws(EvaluationStoreError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .readable
        do {
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            throw .couldNotWrite(path: url.lastPathComponent, reason: "\(error)")
        }
    }

    public static func read(from url: URL) throws(EvaluationStoreError) -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            throw .couldNotRead(path: url.lastPathComponent, reason: "\(error)")
        }
    }
}
