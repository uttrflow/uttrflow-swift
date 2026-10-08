// The clipboard payload schema is independent of the encrypted-file envelope.

package import Foundation
import UttrflowCore

/// The versioned payload persisted by this build. A bare array is the released legacy format.
package struct ClipboardIndex: Codable, Sendable, ElementwiseDecodable {
    package static let currentVersion = 2
    /// The detector version this build stamps on every index it judges; an older stamp is reclassified.
    package static let currentClassifierVersion = 1

    package let version: Int
    package let clips: [Clip]
    package let classifierVersion: Int
    package let hasUnknownJSONKeys: Bool

    package var isLegacy: Bool { version == 1 }
    package var isUnsupported: Bool { !isLegacy && version != Self.currentVersion }

    package init(
        version: Int = Self.currentVersion, clips: [Clip],
        classifierVersion: Int = Self.currentClassifierVersion, hasUnknownJSONKeys: Bool = false
    ) {
        self.version = version
        self.clips = clips
        self.classifierVersion = classifierVersion
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
            classifierVersion = 0
            hasUnknownJSONKeys = false
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        clips = try container.decode([Clip].self, forKey: .clips)
        classifierVersion = try container.decodeIfPresent(Int.self, forKey: .classifierVersion) ?? 0
        hasUnknownJSONKeys = false
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(clips, forKey: .clips)
        try container.encode(classifierVersion, forKey: .classifierVersion)
    }

    private enum CodingKeys: String, CodingKey { case version, clips, classifierVersion }

    /// Refuses JSON this build could decode only by silently discarding fields on its next write.
    package static func containsOnlyKnownJSONKeys(in data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return false }
        let clips: [Any]
        if let legacyClips = root as? [Any] {
            clips = legacyClips
        } else if let index = root as? [String: Any],
            Set(index.keys).isSubset(of: ["version", "clips", "classifierVersion"]),
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
        var classifierVersion = 0
        if let array = root as? [Any] {
            version = 1
            rawClips = array
        } else if let object = root as? [String: Any], let foundVersion = object["version"] as? Int {
            version = foundVersion
            classifierVersion = object["classifierVersion"] as? Int ?? 0
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
            version: version, clips: decoded, classifierVersion: classifierVersion,
            hasUnknownJSONKeys: !containsOnlyKnownJSONKeys(in: data))
        return (index, index.isUnsupported ? [] : rejected)
    }
}
