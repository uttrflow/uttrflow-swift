// Picture-reference bookkeeping, separate from index coordination and byte storage.

/// Protects held and newly written pictures while index writes commit or retry.
struct PictureReferences {
    /// Pictures of deleted clips an undo can still bring back.
    var heldPictures: Set<String> = []
    /// Pictures written for a clip no index names yet.
    var unnamedPictures: Set<String> = []
    /// Pictures a refused write dropped, removed once a later write lands without naming them.
    var picturesAwaitingWrite: Set<String> = []

    /// Takes unreferenced new pictures whose next write can account for them.
    mutating func takeUnnamed(naming named: Set<String>) -> Set<String> {
        let unnamed = unnamedPictures.subtracting(named).subtracting(heldPictures)
        unnamedPictures = []
        return unnamed
    }

    /// Includes removed references from failed writes until a committed list accounts for them.
    func dropped(before: Set<String>, naming named: Set<String>) -> Set<String> {
        before.union(picturesAwaitingWrite).subtracting(named)
    }

    /// Selects disk pictures no index, undo or arrival state references.
    func orphaned(onDisk: Set<String>, wanted: Set<String>) -> Set<String> {
        onDisk.subtracting(wanted).subtracting(heldPictures).subtracting(unnamedPictures)
    }

    /// Selects dropped pictures not held for undo.
    func unheld(_ dropped: Set<String>) -> Set<String> {
        dropped.subtracting(heldPictures)
    }
}
