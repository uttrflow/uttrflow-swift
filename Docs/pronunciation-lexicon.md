# Pronunciation lexicon

`Sources/UttrflowCore/Resources/Lexicon/pronunciation-lexicon.dict` is a trimmed copy of the CMU
Pronouncing Dictionary, pinned by digest in [ngram-sources.md](ngram-sources.md). It is the
lexicon the phoneme-distance candidate sources in [cleanup.md](cleanup.md) read, through
`PhonemeLexicon.bundled` in `UttrflowCore`. Its licence
text, `cmudict-LICENSE.txt`, sits beside it in the same folder and ships in the same bundle.

Which phonemes are heard for one another at half cost is data too:
`phoneme-classes.txt` in the same folder holds one class a line (the vowels, then each voicing
pair), and `PhonemeLexicon` reads it beside the lexicon.


## Words it does not list

A spelling the lexicon does not list (a name, a brand, a romanised Hindi word) is read by the
spelling rules in `letter-sounds.txt`, beside the lexicon: one rule a line, letters then the
phonemes they make, tried in order, with marks for the start of a word, its end and the letter
that must follow. A rule may give a phoneme a second reading ("g" before "e" as in "gem" and
"get"), and the word is then filed under both. The rules are data, so a misread spelling is a
line to add, not code to change.

`WordSound` keys a text by its consonant classes, a leading vowel kept as one mark.
`sound-keys.txt` says which phonemes a key reads as others (each affricate as its fricative, the
r-coloured vowel as a vowel and an r) and which it drops after the first sound (the vowels, the
glides and h). Every text is filed under what the lexicon lists and what its spelling closed up
gives, so a listed run and an unlisted name meet even where the two disagree. Distance, which
decides whether a key match is a reading, uses the lexicon alone for a word it lists.


## How it is derived

```bash
make assets ASSET_CACHE=<folder>   # fetch and check the pinned archives, write the lexicon and its notice, check the digest
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
each, so it is bundled; no download route is needed. That 7,187,293-byte figure is the file's
`budgetBytes` in [data-manifest.md](data-manifest.md), so a rebuild that outgrows it fails.

Reading the file and building a word-to-pronunciations map takes 47.9 ms, best of 5, in a
`swiftc -O` binary (`Data(contentsOf:)`, split by line and space). Host: Apple M5 Pro, measured
under a load average near 150, so the time is an upper bound. It is read once, off the dictation
path.
