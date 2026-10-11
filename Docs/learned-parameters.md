# Learned-parameter files

The small fitted files a quality layer ships (reranker weights, calibration maps, threshold
tables) are read by one type: `LearnedParameters` in
`Sources/UttrflowCore/Support/LearnedParameters.swift`. A layer that parses its own numbers is a
second implementation of this job and is not added. The word tables have their own loader,
described in [data-tables.md](data-tables.md).

## The file

Little-endian. Strings are a `UInt16` byte count and UTF-8 bytes.

| Part | Content |
|---|---|
| Magic | `UTTRLPAR` |
| Format | `UInt32` container version, currently 1 |
| Spec | `UInt32` feature specification version the numbers were fitted under |
| Layer | string, the layer id |
| Engine | string, the recogniser or engine revision fitted for |
| Features | `UInt16` count, then the ordered feature identifiers |
| Arrays | `UInt16` count, then per array: name, `Float32` lower, `Float32` upper, `UInt32` count, the values |

The file's SHA-256 is listed in `Resources/DataManifest.json`. `decode` takes that digest and
refuses a file that does not match it.

## Checks, and what a failure does

| Check | Error |
|---|---|
| Size, counts and name lengths within `LearnedParametersLimits.standard` | `tooLarge`, `tooManyFeatures`, `tooManyArrays`, `tooManyValues`, `invalidName` |
| Magic and container version | `badMagic`, `unsupportedFormat` |
| Spec version equals the layer's | `specVersionMismatch` |
| Layer and engine equal the layer's | `layerMismatch`, `engineMismatch` |
| Feature identifiers equal the layer's, in order | `featuresMismatch` |
| Every value finite and inside its array's range; unique array names | `nonFinite`, `outOfRange`, `invalidRange`, `duplicateArray` |
| No missing or extra bytes | `truncated`, `trailingBytes` |

A mismatch is a refusal, not a warning. `LearnedParametersState.resolve` returns `.dark` with
the reason and logs a fault under the `parameters` category, and the layer runs as if it were
switched off. `LearnedParameters.init` applies the same value checks, so the writer cannot
produce a file the reader refuses for its values. It also encodes a temporary copy to check the
complete file against the supplied byte limit, including UTF-8 names and container overhead.
This allocates encoded bytes during construction, including when the reader delegates to the
constructor; `encoded()` remains the one owner of the layout.
