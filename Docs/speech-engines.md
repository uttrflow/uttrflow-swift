# The speech engines, and what WhisperKit does when nobody is looking

`UttrflowSpeech` (`Sources/UttrflowSpeech/`) drives one recogniser, WhisperKit
(`WhisperKitBackend`, with the `openai_whisper-large-v3-v20240930_turbo_632MB` model), behind
`TranscriptionBackend`. `BackedSpeechEngine` wraps it with what every recogniser needs: the
voice-activity trim ([`silence.md`](silence.md)), the shortest-clip floor, one call at a time, and
loop repair. `SpeechEngineFactory` is the one place that names the concrete recogniser. There is
no second recogniser and no setting that chooses one; see [One recogniser](#one-recogniser). This page holds the
measurements and traps the code relies on. [`bakeoff.md`](bakeoff.md) compares the engines;
[`offline.md`](offline.md) states the no-network rule;
[`speech-vocabulary-prompt.md`](speech-vocabulary-prompt.md) covers the personal-dictionary
prompt; [`speech-model-install.md`](speech-model-install.md) covers installing the model.

| Constant | Value | Meaning |
|---|---|---|
| `BackedSpeechEngine.minimumDuration` | 250 ms | shorter audio is refused as too short |
| `LanguageHeldDecoder.compressionRatioThresholds` | `en`: default, `hi`: 3.0 | one decision per transcribed language; default keeps Whisper's 2.4 |
| `RecognitionLoop.fastestSpeech` | 4.5 words a second | faster than this, a repeated run is a loop |
| `RecognitionLoop.mostCopyDifference` | 0.2 WER | how far copies may differ and still be one loop |
| `RecognitionLoop.fewestCopyWords` | 3 | the shortest copy that counts |
| `CappedDecodeRetry.tokenCapThreshold` | 215 tokens | a decode this long ran out of decoder positions |
| `CappedDecodeRetry.maxRetries` | 10 | re-decodes of the tail after a cap |
| `CappedDecodeRetry.collapsedGapSeconds` | 1.0 s | silence after a window's last word that marks a collapsed window |

## One recogniser

WhisperKit is the recogniser, always. The macOS system recogniser was removed with its setting
(Settings → Dictation → Speed and accuracy), its Diagnostics card and its tests, because it
could not serve the product's promises without a second copy of work WhisperKit already does:

- Hindi is not among its locales, so Hindi and Hinglish dictation lost words or came out in
  English.
- It reported no per-word confidence on most results, so correction could not doubt a word.
- It ignored the conditioning prompt, so the personal dictionary reached it only as weaker
  contextual strings.
- Its first load fetched a system speech asset over the network on the dictation path, which
  [`offline.md`](offline.md) listed as a known gap.

A stored setting that names it decodes to WhisperKit (`EngineConfiguration` falls back to its
default for an unreadable speech kind). A second recogniser returns only as a measured
replacement, with the comparison written here, and the loser deleted.

## Where the speech model runs

`WhisperKitBackend.computeOptions` names the Core ML compute units for each stage rather than
taking the package's defaults, so an upgrade cannot move the model to other hardware unnoticed.
The values equal WhisperKit's own defaults on macOS 14 and later; nothing changed when they were
written down.

| Stage | Compute units |
|---|---|
| Mel spectrogram | `.cpuAndGPU` |
| Audio encoder | `.cpuAndNeuralEngine` |
| Text decoder | `.cpuAndNeuralEngine` |

`WhisperKitContractTests.computeUnitsArePinned` fails if the app's values leave this table or the
linked package's defaults leave the app's.

## Model variants and compute plans, measured

`SpeechComputePlan` names the compute plans a harness may ask for; the app passes only
`.shipping`. Two `uttrflow-eval` options compare candidates without installing them:
`--model-folder` loads any folder from WhisperKit's model repository, and `--compute` picks a
plan. `uttrflow-eval synthesise` fills a corpus with the system voice reading the English
passages, so the comparison needs no microphone.

```bash
uttrflow-eval synthesise --corpus-path ./synth --voice Samantha
/usr/bin/time -l uttrflow-eval transcribe --corpus-path ./synth \
    --model-folder <folder> --compute <plan> --results-path ./results-<name>
```

Host: Apple M5 Pro (Mac17,8), 48 GB, release build. Corpus: the 6 English passages, 305
words, in the Samantha voice. Each row is one fresh process; "load" is the one-minute load
average at the start and end of the run, since other builds shared the machine. Latency is
per passage (typical / slowest). Ready is the engine load, which includes Core ML's first
compile for a variant or plan never loaded before, so a first-run figure is not a warm launch.

| Variant | Plan | WER | Latency | Ready | Peak RSS | On disk | Load |
|---|---|---|---|---|---|---|---|
| `large-v3-v20240930_turbo_632MB` (shipping) | shipping | 3.6% | 1.13 / 1.14 s | 138.2 s (first compile) | 0.77 GB | 618 MB | 18 → 68 |
| `large-v3-v20240930_turbo_632MB` | neuralEngine | 3.9% | 1.09 / 1.13 s | 2.5 s | 0.33 GB | 618 MB | 74 → 80 |
| `large-v3-v20240930_turbo_632MB` | gpu | 3.9% | 1.03 / 6.93 s | 30.4 s | 6.10 GB | 618 MB | 68 → 74 |
| `large-v3-v20240930_turbo_632MB` | all | 3.9% | 1.04 / 2.74 s | 33.4 s | 6.13 GB | 618 MB | 80 → 52 |
| `large-v3-v20240930_turbo_632MB` | cpu | 4.3% | 4.04 / 4.16 s | 20.1 s | 3.55 GB | 618 MB | 52 → 30 |
| `large-v3-v20240930_turbo` (unquantised) | shipping | 4.3% | 1.05 / 1.10 s | 127.8 s (first compile) | 1.62 GB | 1.5 GB | 14 → 18 |
| `large-v3-v20240930_626MB` (full decoder) | shipping | 3.6% | 1.43 / 1.47 s | 65.4 s (first compile) | 0.54 GB | 600 MB | 18 → 29 |
| `large-v3-v20240930_547MB` (full decoder) | shipping | 3.9% | 1.37 / 1.47 s | 11.3 s | 0.48 GB | 527 MB | 29 → 28 |
| `small` | shipping | 4.3% | 0.83 / 0.94 s | 19.5 s | 0.36 GB | 467 MB | 28 → 23 |
| `small_216MB` | shipping | 5.6% | 1.25 / 1.42 s | 15.5 s | 0.30 GB | 210 MB | 23 → 18 |

What the table supports, and what it does not:

- **No candidate beats the shipping model on accuracy.** The spread is 3.6% to 5.6% over 305
  words, where one word is 0.33 points; every large-v3 row is within four words of another.
  The quantised 632 MB build is not worse than its unquantised 1.5 GB source here (3.6% against
  4.3%) and holds less than half the memory.
- **The shipping plan stays.** Moving the encoder and decoder to the GPU, or letting Core ML
  choose, keeps the typical latency, multiplies the slowest passage and holds about 6 GB. The
  CPU alone is about four times slower. `.neuralEngine` (the mel stage on the Neural Engine
  too) matched the shipping plan within the load noise.
- **It cannot decide a switch.** Six synthetic English passages say nothing about Hindi,
  Hinglish, accents or noise, and the machine was not idle. A change of model or plan needs
  the recorded multilingual corpus behind the regression gate first.

## The text decoder's graph, examined

The shipped `TextDecoder` takes one token per call, the whole encoder output (1,280 by 1,500) as an
input on every call, the key and value caches in and out, and holds no Core ML state. Its graph
projects cross-attention keys and values from all 1,500 encoder positions in every layer, on every
token, although they change only once per window.

`Scripts/decoder_compute_plan.swift` reads the model's Core ML compute plan, marks each operation
that depends on the encoder output and on no other input, sums their share of the plan's estimated
cost, and then times single-token steps on zero inputs:

```bash
swiftc -parse-as-library -O Scripts/decoder_compute_plan.swift -o .build/decoder_compute_plan
.build/decoder_compute_plan <Models>/openai_whisper-large-v3-v20240930_turbo_632MB/TextDecoder.mlmodelc 100
```

Apple M5 Pro, 48 GB, one-minute load average 164 to 258 (not idle):

| measure | shipped decoder |
|---|---|
| operations depending only on the encoder output | 32 (the key and value projections and the operations on their results, in each of the 4 layers) |
| their share of estimated cost per step | 0.670 |
| estimated cost preferred on the Neural Engine / CPU | 0.699 / 0.301 |
| median ms per step, 100 steps, first run | 12.2 (82 steps/s) |

**What it settles.** Two thirds of every decoder step is work that is the same for every token of
a window. A decoder that projects the encoder output once per window and keeps the result as state
removes it, so this is the largest per-token lever the recogniser has; prompt length and timestamp
count are ranked after it.

**What it does not settle.** The cost share is Core ML's estimate, not a timing, and the timing
was taken on a loaded Mac, where a second run swung by more than an order of magnitude. Replacing
the decoder needs a stateful build from a publisher with a stated permissive licence, its
provenance recorded in `SpeechModel.swift`, and a WER comparison on the recorded corpus with the
tail wait and memory peak beside it. Until that comparison exists the shipped decoder stays.

**Where a stateful build was looked for.** The publisher the weights come from was searched for a
text decoder that holds the encoder projections as Core ML state:

| repository | stateful text decoder | licence |
|---|---|---|
| `argmaxinc/whisperkit-coreml`, the pinned revision, which is also its head | none: every `TextDecoder` takes the encoder output as an input | MIT |
| `argmaxinc/whisperkit-coreml_01-30-24` | none | none stated |
| `argmaxinc/whisperkit-pro` | yes (`stateSchema` in `TextDecoder.mlmodelc/metadata.json`, five `readState` operations) | proprietary, no redistribution |

The one stateful build cannot ship, so nothing was downloaded and there is no comparison to run.
**Verdict: the shipped decoder stays**, and so does its one decode path. The multi-token entry for
batched prompt prefill and speculative decoding is decided the same way: the pinned folder already
carries `TextDecoderContextPrefill.mlmodelc`, and no permissively licensed multi-token decoder
exists to compare against. Reopened by a stateful decoder published under a permissive licence,
or by converting OpenAI's MIT weights to one inside this repository's own tooling; either is then
measured with `Scripts/decoder_compute_plan.swift` and the recorded corpus as above.

## Keeping WhisperKit off the network

- WhisperKit treats a missing tokenizer as a reason to visit Hugging Face rather than a reason
  to fail. It reaches for one only when it is about to decode, which is the one moment the
  product has promised not to need a network: on a plane that is an unrecoverable failure
  reported as a load error rather than the missing download it is.
- So the tokenizer is fetched at install time over plain HTTPS by `TokenizerDownload`, the one
  file in the module allowed to open a connection (`Scripts/offline_audit.sh` names it as an
  island). A model counts as installed only when the weights *and* both tokenizer files
  (`tokenizer.json` for the vocabulary and merges, `tokenizer_config.json` for the class and
  special tokens) sit directly in the model folder, which is where WhisperKit searches when
  `tokenizerFolder` points there. Left unset, it searches the shared Hugging Face cache under
  `~/Documents` first and downloads into it, state outside anything the app installs or removes.
- `WhisperKit(download: false)` keeps the split honest: the store owns installing, so a missing
  model is a clear error rather than a silent stall on a slow connection.
- The turbo model is a distilled decoder over large-v3's encoder and shares its vocabulary, so
  WhisperKit resolves it to the same tokenizer. The weights are a converted CoreML build; the
  vocabulary is only ever OpenAI's original, which is why `SpeechModel` records both
  repositories.
- The tokenizer download reports no progress. It is well under a percent of the download, and a
  second scale running from zero after the weights reached one would send the bar backwards.

## The shortest clip a recogniser decodes

- WhisperKit starts a decode window only while `seek < clipEnd - windowClipTime * 16000`
  (`Core/TranscribeTask.swift`), and hands the raw array to that loop when no
  `chunkingStrategy` is set. A clip of one second or less therefore never enters the loop and
  decodes to an empty string: a spoken "yes" is about 0.35 s, 0.75 s once `VoiceActivity` has
  kept its 200 ms either side, and unpadded it comes back as "nothing heard". The padding below
  is what lets it through.
- `windowClipTime` exists to keep a window from starting in the last second of audio, where
  Whisper invents words, so it stays at 1.0. `VocabularyPrompt.decodingOptions` names it and
  every other `DecodingOptions` field, so a WhisperKit upgrade that moves a default changes
  nothing here without a diff.
- The floor belongs to the recogniser, not to the engine. `TranscriptionBackend.minimumDuration`
  is each backend's answer: WhisperKit's is `windowClipTime` plus one 20 ms frame, the system
  recogniser's is zero. `BackedSpeechEngine` still refuses anything under its own 250 ms, and
  appends silence to trimmed speech shorter than the backend's floor. The decoder already pads
  every window to 30 seconds with silence, so the appended samples add no signal it did not
  already see; the seek loop runs once over the real speech and stops before the padding.
- The same padding reaches a short final piece of a long dictation that is decoded alone. A final
  fragment under `SpeechWindowing.minimumSpeech` normally joins the window before it
  ([`early-transcription.md`](early-transcription.md)); it goes alone, padded, only where the join
  would pass `maximumLength` or cross a discontinuity.

### Padding, measured

`uttrflow-eval short-clip` decodes the short-utterance class (`ShortUtterances`: 63 replies of one to
three words, English read by every `--voices` voice and romanised Hindi by `--hindi-voice`, each at
the two `--rates`) and six long dictations that end in a 1.5 s pause and one of those replies, each
written by `say` to a file. Arm A scores every padding by clip-length bucket (0.3-0.6 s, 0.6-1.0 s,
1.0-2.0 s) and by language: exact match after normalisation, a word the speaker did not say, empty
output, and a wrong script or language; it also counts the clips the engine's 250 ms floor
refuses. The tables below come from the probe's earlier set of 12 English replies read by four
voices; the class has not yet been measured, and replaces them when it is. It runs the shipping turbo model with the engine's trim and
padding in front of it, language held to English and Hindi, and compares every condition paired
per clip with `PairedBootstrap`. The decision rule was fixed before the run: an alternative
padding replaces the shipped one only if its WER change has a 97.5% interval entirely below 0, of
at least 5 points, for no more than 50 ms of decode time; merging stays unless its WER change
against decoding alone has a 95% interval entirely above 0.

Measured on commit `71510750c7` with the probe added, a debug build on an Apple M5 Pro under a load average of 86,
one pass, synthetic voices only (no recorded human speech).

| Short clips, decoded alone (48, 0.39 to 0.96 s after the trim) | WER | empty | median decode |
|---|---|---|---|
| unpadded | 1.000 | 48 | 3 ms |
| silence appended to the floor (shipped) | 0.068 | 1 | 760 ms |
| silence appended to 2.0 s | 0.068 | 1 | 758 ms |
| 0.5 s of silence before, appended to the floor | 0.068 | 0 | 745 ms |

| Long dictation, short last piece (19 of 24 joined by the windowing) | WER | key-up decode, median |
|---|---|---|
| merged into the window before it (shipped) | 0.003 | 2045 ms |
| decoded alone, padded | 0.006 | 650 ms |

1. **Padding is what makes a short clip decode at all**: every unpadded clip came back empty.
2. **Neither alternative padding changes accuracy**: 2.0 s minus shipped is +0.000 [+0.000,
   +0.000] WER, and leading silence minus shipped is +0.000 [-0.058, +0.068], both 97.5%
   intervals. Both "ship it" errors ("Shibid", "Shitted") appear under every padding, and the
   rest trade places ("sure" empty under the shipped padding, "She or" with leading silence).
   The shipped padding stays.
3. **Merging the last fragment is not shown to change accuracy, and costs time at key-up**:
   merged minus alone is -0.003 [-0.011, +0.003] WER and +1421 ms [+1356, +1488] of key-up
   decode, 95% intervals. Its gain is in the reply itself (alone: "ship it" as "Shibyeaj", "no
   wait" as "No wage"; merged: none), on too few words for the interval to exclude 0. Under the
   rule the join stays. In the other five dictations the windowing kept the reply as a piece of
   its own, so there was no join to compare.

Merging changes only a dictation whose last window is a fragment, so no other corpus case can
move. **Limits.** Debug build, loaded Mac, one pass, four synthetic voices; recorded short
replies would replace both tables.

## Which language the recogniser may answer in

- Detection is held to `LanguageCode.transcribed`, English and Hindi. WhisperKit's own detector
  chooses among every language the model knows, and Urdu sits close enough to Hindi that spoken
  Hindi was sometimes written in Perso-Arabic script, or decoded under the English token and so
  came back translated. Neither can be undone after the recogniser, so the language token is
  constrained before the text is decoded. `LanguageHeldDecoder` wraps WhisperKit's text decoder
  and hands its detector `AllowedLanguageSampler`, which takes the likeliest allowed language.
- The task token is always `transcribe`; `WhisperKitContractTests` and `LanguageHeldDecoderTests`
  both read it back off the options.
- The detector's constraint is the product's languages, not the profile's. Every language
  Settings offers is in the transcribed set, so the profile narrows detection by the hint
  instead: a profile that speaks only Hindi decodes every piece as Hindi, while the default
  English profile and profiles that speak both detect every piece
  (`ListeningLanguages`, `Docs/early-transcription.md`). English alone narrows nothing, because
  `UserProfile.preferredLanguages` starts as English for everyone and pinning it would force
  every Hindi speaker who never opened Settings into English.
- WhisperKit re-runs detection for every fallback temperature and samples it the same way it
  samples text, top-k at that temperature. The allowed sampler ignores the temperature, so one
  window cannot change its language between retries.

## Short Hindi replies under an English and Hindi profile

Measured with `uttrflow-dev bench` (release build, `rt`, shipping cleaner, shipping model,
languages `en,hi`) on 20 clips of 0.29 to 1.06 s made with `say`: eight Hindi replies (`haan`,
`theek`, `theek hai`, `nahi` by `Rishi`; `हाँ`, `ठीक`, `ठीक है`, `अच्छा` by `Lekha`) and twelve
English ones (`ok`, `yes`, and five phrases each by `Rishi` and `Samantha`). Host: Apple M5 Pro,
48 GB, under heavy load, so wall times are not comparable and the cost is counted in decodes.

- **Detection cannot tell them apart.** The Hindi log-probability among the allowed tokens was
  -5.2 to -9.4 on seven Hindi clips, and -5.6 to -16.2 on the English clips; only `ठीक है` was
  detected as Hindi (-0.40). No threshold on the detector's answer flips the Hindi clips without
  flipping `call me later` and `sounds good` spoken by `Rishi`.
- **Decoding both languages and keeping the higher mean log-probability** costs two decodes per
  short piece and changed the kept transcript on one Hindi clip (`nahi`, `Naheen.` to `नहीन`).
  English kept every English clip.
- **The Hindi decode itself misses most of them.** Forced to Hindi, the clips read `हाँ.`, `टीख`,
  `TK`, `हाग?`, `ठीक है.`, nothing, `नहीन`, `अच्चा.`: four of eight carry the reply, so even a
  perfect choice between the two decodes reaches four, against seven asked for. Forcing Hindi also
  turns English clips into Devanagari (`send it` to `संद इख`).

No choice between detection and decoding reaches seven of eight on this model; the ceiling is
the Hindi decode of sub-second audio. The clips are synthetic, and `Rishi` reads romanised
Hindi with an English voice, so `theek` heard as `Teak.` is partly the clip.

## The compression ratio a Hindi decode is judged by

- WhisperKit retries a window warmer when its token ids compress better than 2.4 under zlib, the
  sign of a decode repeating itself. Devanagari is spelled in many short tokens, so a clean
  Hindi decode compresses far better than English does. Measured on the synthetic corpus with
  the shipping turbo model, every greedy decode confident to an average log-probability above
  -0.1: English 1.36 to 1.69, Hindi 1.75 to 2.60. A third of the Hindi windows crossed 2.4.
- A crossed window was re-decoded at temperature 0.2 and upwards, which samples: the same audio
  gave different words on every run, an Arabic letter inside a Devanagari word, and a language
  re-detected by chance. A sampled Hindi decode that really had looped measured 3.91.
- `LanguageHeldDecoder.judged` re-reads a compression verdict for a window decoded as Hindi
  against 3.0, and then applies the log-probability test WhisperKit would have applied next.
  English keeps Whisper's 2.4, and every other verdict is left as WhisperKit gave it.
- The 18 corpus passages, eight runs each, give 96 Hindi and Hinglish transcripts. Without
  either change, 4 were wholly in Perso-Arabic script, 6 had an Arabic letter inside a
  Devanagari word, 1 was translated into English, and overall WER moved between runs from
  12.3% to 18.4%. With both, none of those, every run gives identical text, and overall WER is
  11.8%. English transcripts are unchanged byte for byte.

## A short piece the recogniser wrote twice

- In noise, a short clip can come back as its sentence written twice, often with each copy in
  quotes. For example, a 2.76 s clip of a 7-word Hinglish sentence came back as 14 words. A
  sentence said twice does not compress anywhere near 2.4, so the compression check above cannot
  catch this.
- `RecognitionLoop.undone`, run on every piece `BackedSpeechEngine` transcribes, keeps one copy
  of a repeated run when at least three copies of three or more words differ by no more than 20%
  word error rate and the words come faster than 4.5 a second of speech. A matching trailing
  partial copy is removed with the run. Exactly two copies are checked the same way. A piece that fails the speech-rate or copy-match check is left as heard. So
  a sentence really said twice at a speaking rate keeps both.
- 4.5 words a second is set above the corpus recorder's own "this take was cut off" line (a
  passage read faster than 2.5 / 0.6, about 4.2 words a second) and below the 5.1 of the looped
  clip. It is not measured against recorded speech; measure it with the eval corpus before
  lowering it.
- Double quotes that open the first word and close the last are taken off when there are no
  other quotes in the piece. The recogniser writes these; the speaker did not say them.

## What Devanagari costs, and why Hindi is still decoded in it

Hindi is decoded in Devanagari and romanised afterwards (`Docs/latin-output.md`), so the decoder
spends steps spelling a script the product converts away. Recognition time follows the number of
decoder steps, which makes that density a latency cost rather than a matter of taste.

- **The density, measured off the shipping model's own `tokenizer.json`** over the twelve Hindi and
  Hinglish passages of `Sources/UttrflowEval/TranscriptionCorpus.swift`, whose Devanagari and
  romanised forms are word-for-word parallel:

  | | words | tokens | tokens a word |
  |---|---|---|---|
  | English passages | 302 | 385 | 1.27 |
  | Hindi, Devanagari | 201 | 954 | **4.75** |
  | Hindi, romanised | 201 | 399 | 1.99 |
  | Hinglish, Devanagari | 183 | 684 | 3.74 |
  | Hinglish, romanised | 183 | 311 | 1.70 |

  Devanagari costs 3.7 times English per word. The same words romanised cost 1.6 times, so even a
  decoder that romanised perfectly would not reach English density — the ceiling on this whole
  question is about a 2.4x saving in steps, not a 3.7x one.

- **What the options measure.** `uttrflow-dev transcribe --raw` over the same passages spoken by
  `say` (Hindi and Hinglish by `Lekha` from the Devanagari form, English by `Samantha`), 16 kHz
  mono, every option run against every clip before any option is run twice, so a load spike lands
  on all of them. Load average 4.6 to 24.7.

  | option | ms a word | against English | output script |
  |---|---|---|---|
  | English speech, `en` hint | 21.7 | 1.0x | Latin |
  | Hindi speech, `hi` hint — what ships | 58.8 | 2.7x | Devanagari, 12 of 12 clips |
  | Hindi speech, `hi` hint, dictionary-shaped romanised prompt | 82.7 | 3.8x | Devanagari, 12 of 12 |
  | Hindi speech, `en` hint | 49.4 | 2.3x | Latin, and translated |

  Both alternatives are worse than what ships.

- **A romanised conditioning prompt does not move the script, and costs steps to fail.** Offered the
  romanised words of another passage through `VocabularyPrompt`, every clip still came back in
  Devanagari, and the prompt's own prefill made the decode slower — 82.7 ms a word against 58.8,
  measured at a *lower* load than the baseline row, so the rise is the prompt rather than the
  machine. The only thing that moved was a primed proper noun: `Raghunath` came back as Latin
  `Agunath` inside an otherwise Devanagari sentence, which is a mixed script and a worse spelling.

- **Running romanised text as the prompt moves the script unpredictably, which is worse than not
  moving it.** Given two romanised sentences from other passages as the prompt instead of a word
  list, the twelve clips split: 3 came back wholly in Latin, 6 wholly in Devanagari, and 3 mixed —
  one of them with Perso-Arabic inside it (`late شروع ہوگی`), and one with a Latin fragment glued
  into a Devanagari word (`सunow`). Where it did romanise, the density fell to 1.87 tokens a word as
  predicted, and the spelling was the model's improvisation rather than `Romaniser`'s: `Kal shaam ko
  main` came back as `Kul sham ko mein`, `Kal ka deploy` as `kakla ka diplo`. An output script that
  depends on the clip is not a property the romaniser, the script guard or `LatinScript.enforced`
  can be reasoned about against.

- **Decoding under the English token is the only option that spends fewer steps, and it
  translates.** `हाँ ठीक है…` came back as English prose, which `Docs/latin-output.md` forbids outright. It is
  not even reliably fast: 2 of the 6 pure Hindi clips came back empty, and the times ranged from
  0.72 s to 3.83 s because an English token over Hindi audio trips the thresholds above and
  re-decodes the window warmer, which is how 1.0 tokens a word still measures 2.3x. This is the
  failure the language-token constraint above exists to prevent.

- **No option measured reaches 1.3x**, and the only one whose density could — English tokens over
  Hindi audio — gets there by translating. Romanised decoding would land near it if it were
  reliable: the fixed encoder cost is most of a short dictation, so 1.99 tokens a word against
  English's 1.27 works out at about 1.2x by the step model above. It is the reliability that fails,
  not the arithmetic.

**So Devanagari stays.** The density is the tokenizer's property, not this repository's, and every
way of spending fewer steps on it changes what the speaker sees: a translation, a spelling nobody
tested, or a script that varies clip to clip. A 2.4x saving in decoder steps is real, and only a
decoder that writes romanised Hindi as its own output, rather than one talked into it, could take
it ([`measuring-accuracy.md`](measuring-accuracy.md)).

**What these numbers are not.** The clips are synthetic, and synthetic Hindi speech is not a stand-in
for recorded speech ([`measuring-accuracy.md`](measuring-accuracy.md)), so these figures rank the
options against each other and assert nothing about how well the product hears Hindi. Word accuracy
here was scored word by word against the parallel references with a grapheme-aware split, not
through `Scripts/dictation_bench.py`, whose Hindi rate is counted over letter fragments and is
therefore not a word error rate.

## Why one noisy clip answers differently every run

- A two-word reply mixed with brown noise at 10 dB SNR (`reply4-daniel-snr10`, "Ship it") was
  inserted as "Shit is." in 16 of 50 runs and refused as "Didn't catch that." in the other 34, on
  byte-identical audio; a second 50 split 23 to 27. Sampling in the temperature ladder was the only
  randomness in a decode, so which of the two a run gave was which draw landed. The ladder now
  draws from a fixed seed ([`decode-session.md`](decode-session.md)), so a window handed the same
  logits draws the same tokens on every run.
- **The ladder does not invent the words.** With `firstTokenLogProbThreshold` unset, the greedy
  decode of that clip is the same misreading on every run, at an average log-probability of -0.297
  and a compression ratio of 0.86 — confident against every threshold the options carry, and 0.02
  away from the -0.275 the same clip scores when it is read correctly as synthesised. The
  near-homophone is the model's own first reading of this audio at this level of noise; the
  clip as synthesised and at 20 dB SNR both read "Ship it." The ladder decides whether the
  misreading is shown, never what it is.
- **`firstTokenLogProbThreshold: -1.5` is what makes the outcome a draw.** It ends a window at its
  first sampled token when that token scores below the threshold, leaving no tokens at all
  (`Core/TextDecoder.swift:674` and `:686`). In a timestamped decode that first token is the
  segment's opening timestamp, so noise over a 0.6 s clip fails it on where the speech starts
  rather than on any word. WhisperKit reads the check ahead of the silence test
  (`Core/Models.swift:366`, "order matters here"), so such a window never gets a no-speech
  probability and is retried warmer instead of being discarded as silence. It fired at temperature
  0 on all 50 runs, and at 1.0 on the 34 that ended empty.
- **The silence test cannot fire at all in the WhisperKit this package pins.** The decoder sets
  `noSpeechProb` to a constant 0 (`Core/TextDecoder.swift:817`, marked as not yet implemented), so
  `noSpeechThreshold: 0.6` is never exceeded, neither in the fallback verdict
  (`Core/Models.swift:369`) nor in the segment skip (`Core/Text/SegmentSeeker.swift:59`). That is
  why moving the threshold to 0.4 or 0.8 changes nothing on non-speech clips (#2430). A window of
  breath, cough or key noise therefore ends empty at temperature 0 on the first-token check and is
  sent up the ladder, where a warmer draw can return a sound caption that differs run to run.
  Refusing the ladder for such a window needs a real no-speech probability (the `<|nospeech|>`
  token's probability at the start-of-transcript position) computed outside WhisperKit, or a
  decision that a first-token rejection at temperature 0 is final.
- The ladder keeps the first draw that passes the thresholds and otherwise the last one
  (`Core/TranscribeTask.swift:327-405`). Every one of the 16 words came from temperature 0.8;
  0.2 to 0.6 were rejected every time, and the 34 empties are the abandoned decode at 1.0.
- **Neither a word list nor a confidence floor separates the misreading from a correct
  transcript.** Rejecting a fallback result that adds a listed word the greedy result lacks
  compares against a greedy result with no words in it, so it fires on the accident that the
  window was abandoned; the moment the first-token check passes, the misreading *is* the greedy
  result and the comparison sees nothing. The average log-probability the ladder accepts on is
  0.02 apart for the right and the wrong reading, which no floor can sit between. The per-word
  figure does separate this pair — 0.19 for the wrong word against 0.71 for the right one — but
  `Docs/ai-correction-thresholds.md`
  measures why one per-word score is not a licence to move a word: recognisers are unsure
  constantly, and correction needs three independent conditions before one word changes.
- What is left is recognition accuracy at that level of noise, which is a model and a front-end
  question rather than a decoding one. `Scripts/dictation_bench.py score` reports every clip run
  more than once that answered differently, so the class is visible in an ordinary bench run
  rather than only in a hand-built one.

## The temperature fallback, swept

`SpeechFallbackPlan` holds the fallback count and the log-probability test; the product ships
Whisper's own (5 steps, -1.0). `uttrflow-eval fallback-sweep` decodes the spoken clips under each
plan several times, clean and with seeded white noise, and reports the share of decodes that fell
back, the extra seconds (mean and worst per piece), the share of clips whose runs all agree, and
word error rate.

```bash
uttrflow-eval fallback-sweep --per-voice 2 --runs 3 --snrs inf 10
```

Host: Apple M5 Pro, 48 GB, release build, large-v3 turbo. 8 English clips (2 per voice), 3 runs
each, 16 minutes on a loaded machine. Every row is the same:

| Audio | Count | Log-prob | Fallback rate | Mean extra s | Worst extra s | Identical | WER |
|---|---|---|---|---|---|---|---|
| clean, 10 dB | 5, 0, 1, 2 | -1.0 | 0.0% | 0.000 | 0.00 | 100.0% | 0.0% |
| clean, 10 dB | 5 | -0.7, -1.3 | 0.0% | 0.000 | 0.00 | 100.0% | 0.0% |

On this set the fallback never fires, so no setting changes words, seconds or repeatability, and
the shipping plan stays. The set cannot decide the question: the recorded and degradation corpora,
Hindi, short utterances and 8 runs are not measured here, and the log-probability test still reads
a mean that counts forced tokens.

## Per-word confidence

- Correction's first condition is that the recogniser was unsure. Without a per-word figure the
  condition can only be answered with a constant, which makes it either always true (the engine
  rewrites constantly) or never true (it can never fire). `RawWord.probability` comes from
  WhisperKit's `WordTiming.probability`, which is why `wordTimestamps` is asked for.
- Measured on the shipping turbo model: +4.1 ms on a 3.3 s clip and +19.1 ms on a 24.3 s one,
  0.9% and 1.4% of those transcriptions. The spread is real: "up" at 0.41 beside content words
  at 0.99 in the same sentence.
- Absent still means "not reported", never "all confident".

## The conditioning prompt

- The user's own words are offered to Whisper as the prompt it is conditioned on before it
  decodes anything. Rewriting "utter flow" to "Uttrflow" afterwards is a repair that only fires
  when the recogniser produced something close enough; putting the word in front of the decoder
  makes it hear the word. `VocabularyPrompt` builds it; `DictionaryVocabulary` bridges the
  ranking (`WorkingSet`) to it.
- Handed a bare run of words (`Uttrflow Nikhil PaymentSheet`) the decoder barely moves: it still
  heard "KidPit". Handed the same words inside the sentence " The words used here are" it heard
  "Uttrflow", with three words in the list and again with fourteen. Whisper's prompt is trained
  as the transcript that came before, so text shaped like a transcript is what it conditions on.
- The real prompt ceiling is 111 tokens, not the model's 448-token context and not half of it:
  WhisperKit trims the prompt to `(Constants.maxTokenContext / 2) - 1` and `maxTokenContext` is
  `Int(448 / 2)` (WhisperKit 1.1.0, `Core/TextDecoder.swift:199` and `Core/Models.swift:1340`;
  `WhisperKitContractTests` asserts the derivation against the linked package).
  It keeps the *last* 111 tokens and drops the rest without a word, so a best-first vocabulary
  would lose precisely the words worth having; the prompt is packed word by word here instead,
  skipping a word that does not fit rather than stopping.
- The prompt is applied once ahead of the prefill and re-forced for every 30-second window:
  WhisperKit builds the decoder's initial prompt before its seek loop and never overwrites it.
- The empty vocabulary, an absent tokeniser, or a prompt nothing survives leaves the decoding
  options untouched. A word missing from the prompt costs the user a correction; a dictation
  refused because a word would not encode costs them the dictation.

## The rules a prompt costs the decode

- WhisperKit's timestamp rules forbid the `<|notimestamps|>` token, keep timestamps paired and
  rising, and force each segment to have a nonzero length — which is what stops a window
  repeating itself until the compression-ratio threshold catches it six temperature retries
  later. They are installed as a `TimestampRulesFilter` whose `sampleBegin` is re-derived from
  the token array by looking for the task token in its first three tokens
  (`Core/Text/LogitsFilter.swift:137-148`).
- A conditioning prompt puts the task token past those three, because the prefill it builds is
  `[<|startofprev|>] + prompt + [<|startoftranscript|>, language, task, timestamps]`
  (`Core/TextDecoder.swift:163-223`), and prompt tokens are filtered below `specialTokenBegin`
  at both ends so none of them can ever be it. The derivation then returns nothing and the
  filter returns the logits untouched for the whole decode — so a user with a personal
  dictionary decoded with no timestamp rules at all, and a user with an empty one decoded with
  them.
- `DecoderPrefill` counts the prefill the decoder is actually given and installs the rules with
  that `sampleBegin`, reporting the model as English-only so they trust the number rather than
  hunting for a token a prompt has moved. WhisperKit still appends its own inert copy beside
  ours, which costs an early return per step. `DecoderPrefillTests` holds the behaviour.
- No filter holds the end token shut during the prefill. A filter keyed on
  `tokens.count == prefill` matches every prefill iteration *and* the first sampled token, because
  the token array does not grow while the prompt is forced, so no logits filter can tell those
  steps apart. WhisperKit 1.1.0 ignores an end token sampled during its own prefill
  (`Core/TextDecoder.swift:679`) and honours one sampled at the last prefill token, where it is a
  real prediction that the window holds no speech; such a filter would only suppress that
  prediction.
- A blank biased transcription is re-run without the vocabulary
  (`CappedDecodeRetry.transcribeRecoveringEmptyPrompt`): a WhisperKit release or model variant
  that finds another way to return nothing must cost the user a slower dictation, never a silent
  one. Silence transcribes to nothing too, so this can
  decode twice for no gain, which is the right price.

## One call into the recogniser at a time

A loaded WhisperKit is one set of models with shared decoder state: the logits filters a
prompted decode installs live on the kit, not on the call. Two decodes on one kit at once
therefore read each other's rules, and on a slow Mac they also split the same CPU and memory.

An actor does not prevent that. Every `await` inside an actor method lets the next caller
in, and a decode is nothing but awaits, so `WhisperKitBackend` being an actor serialises
nothing across a transcription. Nor does the pipeline: a stage that times out is cancelled
and not awaited (see `Docs/stuck-recording.md`), and cancelling a dictation abandons its
decode without cancelling it at all, so a dictation started straight afterwards reaches the
recogniser while the old decode is still running.

`BackedSpeechEngine` therefore holds a `RecogniserTurn` across every load and decode. Calls
are admitted one at a time in the order they arrived; a later call waits for the earlier one
to leave the recogniser, and a waiter that is cancelled — the pipeline's stage timeout does
exactly that — leaves the queue and never decodes. The wait is bounded by the same stage
limit as the decode, so a dictation stuck behind a wedged decode fails and names a retry
rather than showing "transcribing" for ever.

Measured with the default model on synthetic speech: a cancelled decode stops within about
ten milliseconds, since WhisperKit checks for cancellation before every decoder step, so
after a timeout the wait is short. After a cancelled dictation it is the rest of that
decode. Without the turn, four overlapping decodes on one kit, two with a prompt and two without, returned
the unprompted text for both prompted decodes in one round of three: the filters of one
call had been replaced by another's.

## Word timings behind a prompt

- WhisperKit's `SegmentSeeker.addWordTimestamps` reads the decoder's alignment weights from row
  zero, taking it as the start-of-transcript token. Behind a conditioning prompt that row is the
  start-of-previous token, and the transcript's rows begin at `prompt.count + 1`, so every word is
  aligned against the prompt instead (WhisperKit 1.1.0, `Core/Text/SegmentSeeker.swift`).
- The misaligned timings are not only wrong, they lose words. `TranscribeTask` drops a segment
  whose word timings collapse to zero length, and advances `seek` to the last segment's end, which
  a bad alignment can place past audio never decoded. Sentences vanish from the start, the middle
  or the end of the dictation, and the same audio with the same prompt loses the same ones.
- Measured on synthetic speech from `say`, three voices, eight clips from 5 to 55 seconds, five
  runs each with no prompt and with 5, 20 and 100 dictionary words: 45 of the 120 prompted
  decodes lost at least one sentence, 215 sentences in all, and none of the unprompted ones did.
  With the rows lined up, none of the 120 lost a sentence.
- `PromptAlignedSegmentSeeker` hands WhisperKit's own seeker the weights from the transcript's
  first row onward; `DecoderPrefill.transcriptStart` counts the offset from the same trimmed prompt
  the timestamp rules are measured from, and an unprompted decode keeps WhisperKit's seeker. The
  seeker lives on the kit like the filters, so the turn above is what keeps one call's offset from
  reaching another's decode.
- A separate failure survives the alignment: with 100 words, one 53-second clip's first window
  came back as a single segment with no inner timestamps, so the window ended at its fixed 30
  seconds and the four words spoken across that boundary were lost. That is the decoder's
  segmentation under a long prompt, not the alignment.
- `CappedDecodeRetry.collapsedWindow` catches that shape: a segment that ends at a 30-second
  window (or spans a whole one) while its last word ends more than a second before it, with audio
  still after it. The segments after it are dropped and the audio is decoded again from that last
  word, so the boundary words are recovered at the cost of one extra decode of the remainder,
  paid only when a window collapses. Unit-tested against a fake recogniser (`CappedDecodeTests`);
  the cost on real audio is not measured.

## A decode that ran out of decoder positions

The prompt and the transcript share WhisperKit's 223 decoder positions
([`speech-vocabulary-prompt.md`](speech-vocabulary-prompt.md)), and Devanagari spends about 4.7
tokens a word, so a long Hindi piece can stop mid-word because the decoder ran out of room rather
than because the speech ended. `CappedDecodeRetry` treats a decode of `tokenCapThreshold` (215)
tokens or more as capped; a backend that does not report tokens is judged by its last segment
ending more than `RawTranscript.cappedDecodeGap` (2.5 s) before the audio does. It keeps the
segments up to the last ordinary word (a final word that lands at the slice end is the recogniser's
fragment, whether stretched to fill the audio or hallucinated onto a short late stretch) and
decodes the rest again, up to `maxRetries` (10) times. A dictation still capped when the retries
run out, or with no point to resume from, is marked `DecodeEffort.capUnresolved` rather than
returned as if it were complete.
