# Pronunciation lexicon

`Sources/UttrflowCore/Resources/Lexicon/pronunciation-lexicon.dict` is a trimmed copy of the CMU
Pronouncing Dictionary, pinned by digest in [ngram-sources.md](ngram-sources.md). It is the
lexicon the phoneme-distance candidate sources in [cleanup.md](cleanup.md) read. Its licence
text, `cmudict-LICENSE.txt`, sits beside it in the same folder and ships in the same bundle.

## How it is derived

```bash
python3 Scripts/ngram_sources.py --fetch --cache <folder>   # fetch and check the pinned archives
python3 Scripts/derive_lexicon.py --cache <folder>          # write the lexicon and its notice
make data-manifest                                          # then record the new digest
```

The script refuses a cache the source check refuses. A word is kept when:

1. it occurs at least 20 times (`MIN_COUNT`) across the text files of the pinned `text` sources,
   counted lower-case; or
2. one of its listed pronunciations is within weighted phoneme distance 1 of a pronunciation of a
   word kept by rule 1. A vowel for a vowel or a voicing pair costs 0.5, any other edit 1, stress
   marks dropped, as in [cleanup.md](cleanup.md); same sound is distance 0.

Every listed pronunciation of a kept word is kept, alternatives (`word(2)`) included, in the
source's own line format and order. The file is generated: change the script or the pin, never
the file.

The frequency source is the pinned technical text, not a general word list, because it is the
only frequency source with a recorded licence. It under-counts everyday words, which rule 2
partly recovers; a general frequency list is a new pinned source and goes through the allowlist.

## Size and load time

| Min count | Frequent words | Kept words | Listings | Bytes | gzip -9 | xz -9 |
|---|---|---|---|---|---|---|
| 5 | 10,108 | 46,137 | 50,021 | 1,066,826 | 278,324 | 224,068 |
| **20 (shipped)** | **6,465** | **38,151** | **41,281** | **844,809** | **224,112** | **179,900** |
| 50 | 4,639 | 32,823 | 35,492 | 704,876 | 189,502 | 151,960 |

Against [data-asset-delivery.md](data-asset-delivery.md), which budgets a bundled lexicon at about
7.2 MB installed and 1.5 MB compressed, the shipped file is about 12% of
each, so it is bundled; no download route is needed.

Reading the file and building a word-to-pronunciations map takes 47.9 ms, best of 5, in a
`swiftc -O` binary (`Data(contentsOf:)`, split by line and space). Host: Apple M5 Pro, measured
under a load average near 150, so the time is an upper bound. It is read once, off the dictation
path.
