import Foundation

/// The sealed index records which detector judged its clips.
struct ClipboardIndex: Codable, Sendable {
    static let currentClassifierVersion = 1

    let classifierVersion: Int
    let clips: [Clip]

    init(clips: [Clip], classifierVersion: Int = Self.currentClassifierVersion) {
        self.classifierVersion = classifierVersion
        self.clips = clips
    }

    init(from decoder: any Decoder) throws {
        if let values = try? decoder.container(keyedBy: CodingKeys.self) {
            classifierVersion = try values.decode(Int.self, forKey: .classifierVersion)
            clips = try values.decode([Clip].self, forKey: .clips)
        } else {
            classifierVersion = 0
            clips = try decoder.singleValueContainer().decode([Clip].self)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case classifierVersion
        case clips
    }
}
