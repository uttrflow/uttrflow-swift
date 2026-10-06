# N-gram sources

`Resources/NgramSources.json` lists every text source the shipped technical n-gram table may be
built from. The table is a build input, not a resource file; the file it produces is listed in
[data-manifest.md](data-manifest.md) like any other bundled file. The user model is built on the
device from the person's own history and is never merged into the shipped table.

## The pinned sources

| Source | Licence | Why |
|---|---|---|
| `swift-book` | Apache-2.0 | the Swift language's own prose, the vocabulary of this app's users |
| `cpython` | PSF-2.0 | the Python documentation and docstrings |
| `django` | BSD-3-Clause | web-framework documentation in a long-established project |

Each archive is a tagged release, so its bytes are fixed; the digest proves it on every fetch.
Technical writing is not dictation, so the table is one input among several, and its effect is
measured with `make bakeoff` when it is built.

## Fields

| Field | Meaning |
|---|---|
| `name` | a short identifier for the source |
| `publisher` | the project that publishes the text |
| `url` | the exact archive downloaded |
| `revision` | the release tag or commit of that archive |
| `licence` | an SPDX identifier from the allowlist below |
| `archive` | the file name of the archive in the snapshot cache |
| `sha256` | the archive's digest |
| `fetched` | the day the archive was downloaded, `YYYY-MM-DD` |

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

It fails when an entry lacks a field, names a licence outside the allowlist, or has a malformed
digest or date. With `--cache` it also fails when the folder holds an archive the manifest does
not list, a listed archive is missing or its digest differs, or the folder is under
`Application Support`. The cache lives outside the repository, and each archive is downloaded
once. A build script runs this check first and reads only the archives it passed.
