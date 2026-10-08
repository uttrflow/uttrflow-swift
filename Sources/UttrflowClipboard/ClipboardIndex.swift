// The clipboard payload schema is independent of the encrypted-file envelope.

package import Foundation
import UttrflowCore

/// The versioned payload persisted by this build. A bare array is the released legacy format.
package struct ClipboardIndex: Codable, Sendable, ElementwiseDecodable {
    package static let currentVersion = 2

    package let version: Int
    package let clips: [Clip]
    package let hasUnknownJSONKeys: Bool

    package var isLegacy: Bool { version == 1 }
    package var isUnsupported: Bool { !isLegacy && version != Self.currentVersion }

    package init(
        version: Int = Self.currentVersion, clips: [Clip], hasUnknownJSONKeys: Bool = false
    ) {
        self.version = version
        self.clips = clips
        self.hasUnknownJSONKeys = hasUnknownJSONKeys
    }

    package init(from decoder: any Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var legacyClips: [Clip] = []
            while !array.isAtEnd {
                legacyClips.append(try array.decode(Clip.self))
            }
            version = 1
            clips = legacyClips
            hasUnknownJSONKeys = false
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        clips = try container.decode([Clip].self, forKey: .clips)
        hasUnknownJSONKeys = false
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(clips, forKey: .clips)
    }

    private enum CodingKeys: String, CodingKey { case version, clips }

    /// Refuses JSON this build could decode only by silently discarding fields on its next write.
    package static func containsOnlyKnownJSONKeys(in data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return false }
        let clips: [Any]
        if let legacyClips = root as? [Any] {
            clips = legacyClips
        } else if let index = root as? [String: Any],
            Set(index.keys).isSubset(of: ["version", "clips"]),
            let currentClips = index["clips"] as? [Any]
        {
            clips = currentClips
        } else {
            return false
        }

        return clips.allSatisfy { value in
            guard let clip = value as? [String: Any],
                Set(clip.keys).isSubset(of: Clip.persistedJSONKeys)
            else { return false }
            guard let image = clip["image"], !(image is NSNull) else { return true }
            guard let imageFields = image as? [String: Any] else { return false }
            return Set(imageFields.keys).isSubset(of: ClipImage.persistedJSONKeys)
        }
    }

    package static func decodeEachElement(from data: Data) throws -> (value: Any, rejected: [Data]) {
        let root = try JSONSerialization.jsonObject(with: data)
        let version: Int
        let rawClips: [Any]
        if let array = root as? [Any] {
            version = 1
            rawClips = array
        } else if let object = root as? [String: Any], let foundVersion = object["version"] as? Int {
            version = foundVersion
            let foundClips = object["clips"] as? [Any]
            guard foundClips != nil || foundVersion != currentVersion else {
                throw CocoaError(.fileReadCorruptFile)
            }
            // Decode future schemas for display, but keep them opaque to quarantine and write paths.
            rawClips = foundClips ?? []
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var decoded: [Clip] = []
        var rejected: [Data] = []
        for rawClip in rawClips {
            let record = try JSONSerialization.data(
                withJSONObject: rawClip, options: [.fragmentsAllowed, .sortedKeys])
            if let clip = try? JSONDecoder().decode(Clip.self, from: record) {
                decoded.append(clip)
            } else {
                rejected.append(record)
            }
        }
        // Future payloads must never be quarantined, set aside, or rewritten by this older build.
        let index = ClipboardIndex(
            version: version, clips: decoded, hasUnknownJSONKeys: !containsOnlyKnownJSONKeys(in: data))
        return (index, index.isUnsupported ? [] : rejected)
    }
}
