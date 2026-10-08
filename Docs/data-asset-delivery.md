# Delivering data assets: bundled or downloaded

Three planned dictation assets have no file yet: a lexicon, an n-gram table and vocabulary
packs. Two delivery routes already exist in the app: resources sealed into the bundle and
listed in [data-manifest.md](data-manifest.md), and the pinned-digest download that installs
the speech weights ([speech-model-install.md](speech-model-install.md)). No third route is
added. This page holds the measurement each choice is made from.

## What ships today

| Item | Bytes |
|---|---|
| Bundled resource files, all 23 in `Resources/DataManifest.json` | 3,267,254 |
| Built `Uttrflow.app`, `du -sk` | 115,671,040 |
| Release disk image, `Uttrflow-0.5.0.dmg` | 14,485,057 |
| Speech weights download, `SpeechModel.largeV3Turbo.downloadBytes` | 645,668,913 |
| One word table, `DataTableLimits.standard.maxBytes` | 65,536 |

## Stand-in assets, measured

The assets do not exist, so each is stood in for by a file of the expected shape: the
lexicon is the 235,976-word system list (`/usr/share/dict/words`) with a count per word;
the n-gram table is random word pairs with a count, at two sizes; a vocabulary pack is
2,000 words. Each is compact JSON in the `DataTable` file shape. Load time is the best of 3
runs of `Data(contentsOf:)` plus `JSONSerialization.jsonObject` in a `swiftc -O` binary.

| Stand-in | JSON bytes | zlib -9 | xz | Load |
|---|---|---|---|---|
| Vocabulary pack, 2,000 rows | 39,180 | 12,036 | 11,340 | 0.4 ms |
| Lexicon, 235,976 rows | 7,187,293 | 1,862,780 | 1,473,132 | 73.8 ms |
| Bigrams, 100,000 rows | 3,300,112 | 1,483,214 | 1,126,612 | 39.7 ms |
| Bigrams, 1,000,000 rows | 33,029,087 | 14,826,479 | 9,845,496 | 399.1 ms |

Host: Apple M5 Pro, 48 GB, measured under a load average near 70, so the load times are an
upper bound.

## What the numbers say

- A lexicon, a 100,000-pair table and any number of packs add about 3.5 MB to the disk image
  and 10.5 MB to the installed app. That is a quarter of today's image and under 10% of the
  app, against a speech download of 646 MB.
- A 1,000,000-pair table adds 10 to 15 MB to the image, about doubling it, and 33 MB
  installed. It loads in 0.4 s, so it is read once off the dictation path, never per
  utterance.
- Every stand-in except a pack is larger than `DataTableLimits.standard`, so each needs its
  own stated limit in the one loader, not a second loader.

## Update path for each route

| | Bundled | Pinned-digest download |
|---|---|---|
| Verification | notarisation and the update signature | the digest pinned in the release |
| A new asset reaches the user | with the next app update | with the next app update, since the digest is pinned in the binary |
| Works offline after install | yes | only once downloaded |
| New network code | none | none; it reuses the speech installer |
| Change to [offline.md](offline.md) | none | a new install-time row |

Because the download's digest is pinned in the binary, neither route updates an asset between
releases; an asset that must change more often than the app needs a signed index, which is a
new route and is not proposed here.
