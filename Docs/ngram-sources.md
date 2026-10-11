# N-gram sources

`Resources/NgramSources.json` lists every source a shipped data file is built from: the text
sources of the technical n-gram table (`kind: text`) and the pronunciation lexicon
(`kind: lexicon`). Both are fetched by digest through the one check below. The table is a build input, not a resource file; the file it produces is listed in
[data-manifest.md](data-manifest.md) like any other bundled file. The user model is built on the
device from the person's own history and is never merged into the shipped table.

## The pinned sources

| Source | Licence | Why |
|---|---|---|
| `swift-book` | Apache-2.0 | the Swift language's own prose, the vocabulary of this app's users |
| `cpython` | PSF-2.0 | the Python documentation and docstrings |
| `django` | BSD-3-Clause | web-framework documentation in a long-established project |

## The pronunciation lexicon

| Source | Licence | Why |
|---|---|---|
| `cmudict` | BSD-2-Clause | the CMU Pronouncing Dictionary, which defines "same sound" in [cleanup.md](cleanup.md) |

It is not in the public domain. Its licence asks that the copyright notice, the conditions and
the disclaimer travel with every copy in source or binary form, so the entry names `notice`, the
tracked copy at `Resources/Notices/cmudict-LICENSE.txt`, and `noticeInArchive`, the same text
inside the pinned archive. The check fails when the two differ, so a new revision with
different terms cannot be built from unnoticed. The bundled file derived from it ([pronunciation-lexicon.md](pronunciation-lexicon.md)) ships that
notice beside it, as `LICENSE-bip39.txt` does for its word list.

The pinned revision holds 135,166 entries, 9,114 of them alternative pronunciations (`word(2)`).
Alternatives are kept in any derived file: "same sound" compares every listed pronunciation, and
"affect" and "effect" match only through effect's third.

Each archive is a tagged release or a commit, so its bytes are fixed; the digest proves it on
every fetch.
Technical writing is not dictation, so the table is one input among several, and its effect is
measured with `make bakeoff` when it is built.

## Fields

| Field | Meaning |
|---|---|
| `name` | a short identifier for the source |
| `kind` | `text` for an n-gram text source, `lexicon` for a pronunciation lexicon |
| `publisher` | the project that publishes the text |
| `url` | the exact archive downloaded |
| `revision` | the release tag or commit of that archive |
| `licence` | an SPDX identifier from the allowlist below |
| `archive` | the file name of the archive in the snapshot cache |
| `sha256` | the archive's digest |
| `fetched` | the day the archive was downloaded, `YYYY-MM-DD` |
| `notice`, `noticeInArchive` | for a lexicon: the tracked licence text, and its path inside the archive |

## What is allowed

Official documentation and source repositories of well-established open-source projects under
`MIT`, `BSD-2-Clause`, `BSD-3-Clause`, `Apache-2.0`, `PSF-2.0` or `CC0-1.0`.

## What is excluded, and why

| Class | Why |
|---|---|
| Share-alike licences | a count table derived from the text may be a derivative under the same licence; excluded until a licence decision is recorded |
| No-derivatives licences | a count table is a derivative |
| Forum, mail and chat text | holds real people's words and names, which no tracked file or bundle may carry |
| Personal blogs and scraped web text | unknown licence, and real people's words |
| Anything on this Mac under `Application Support` | that is the user's own history; it builds the on-device user model only and never enters the shipped table |

## The check

```bash
make data-manifest                                   # includes the n-gram source check
python3 Scripts/ngram_sources.py --cache <folder>          # before a build reads a snapshot cache
python3 Scripts/ngram_sources.py --fetch --cache <folder>  # download missing archives, then check
```

It fails when an entry lacks a field, names a licence outside the allowlist or a kind outside
the two, has a malformed digest or date, or is a lexicon without a tracked notice. With `--cache` it also fails when the folder holds an archive the manifest does
not list, a listed archive is missing or its digest differs, a lexicon's licence text differs
from its tracked notice, or the folder is under
`Application Support` or inside the repository. The cache lives outside the repository, and each archive is downloaded
once. A build script runs this check first and reads only the archives it passed.
