# What a build does with a learned-state file another build wrote

A learned store holds aggregates the user cannot type back in. Going back one version, or a
file that fails to decode, must not cost them. This page is the one rule set every versioned
learned store follows; the evidence ledger ([learned-state.md](learned-state.md)) is the store
that holds the persona, and the table at the end says how far it meets each rule.

## The rules

1. **The version is inside the file.** An integer `schemaVersion` sits beside the contents. The
   file name also carries a version (`evidence.v1.json`), but that names a shape too different
   to read in place, not a revision of this one.
2. **A newer file is never changed by an older build.** A reader whose supported version is
   lower opens nothing, writes nothing and deletes nothing; the file stays byte-identical. The
   feature that reads it is off for that launch and Diagnostics says why. Only the user's own
   reset deletes it.
3. **An older file is migrated in memory first.** The reader decodes the old shape, converts it,
   and writes the new version only after a copy of the old file is kept for one release.
4. **Unknown fields survive a round trip where the format allows**, so a field a newer build
   added is not stripped by a build that only rewrote the rows it knows.
5. **A file that cannot be read is refused, not replaced.** A write over an unreadable file
   would replace rows nobody has seen; the store throws instead.
6. **Primary fields and recomputable fields are told apart.** A primary field is an
   observation that exists nowhere else; it keeps its own retention and a downgrade rule. A
   recomputable field is a projection of primary fields or of History, and is rebuilt rather
   than migrated. When a file cannot be read, rebuilding what is recomputable is offered.

## The evidence ledger today

| Rule | State | Where |
|---|---|---|
| 1. version inside the file | met: `schemaVersion` 1 | `EvidenceLedgerFile` in `Sources/UttrflowCore/Support/EvidenceLedgerStore.swift` |
| 2. newer file left byte-identical | met: read by its `schemaVersion` alone, even when its rows do not decode here; reads return no rows, writes throw `newerVersion` | `EvidenceLedgerStoreTests.newerVersionWithUnknownRowsIsLeftInPlace` |
| 2. Diagnostics note for a newer file | met: a "Learned state" attention row | `EvidenceLedgerStore.refusal()` |
| 3. older file migrated after a kept copy | nothing to migrate: version 1 is the only released shape, held as a byte fixture | `EvidenceLedgerStoreTests.releasedVersionOneFixtureReads` |
| 5. one undecodable row costs only itself | met: kept aside as a quarantine record, the readable rows stay usable | `EvidenceLedgerStoreTests.undecodableRowAtCurrentVersionIsQuarantined` |
| 4. unknown fields kept | not needed while rule 2 holds: no build rewrites a file newer than itself | |
| 5. unreadable file refused | met: writes throw `unreadable` | `EvidenceLedgerError.unreadable` |
| 6. recompute offered when unreadable | not yet | |

## Primary and recomputable fields in the ledger

| Field | Kind | Source |
|---|---|---|
| `EvidenceRow` with provenance `dictation`, `undo` or `user` | primary | written when the observation happens; nowhere else holds it |
| `EvidenceRow` with provenance `migration` | recomputable | backfilled from History dictations older than the first live row (`EvidenceSources.backfill`) |
| Projections (`netUses`, style rates, spelling and pair preferences) | recomputable | summed from the rows on every read |

Ledger rows follow the History retention window ([learned-state.md](learned-state.md#where-the-ledger-lives)).
