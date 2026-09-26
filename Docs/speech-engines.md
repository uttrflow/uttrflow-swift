# The speech engines, and what WhisperKit does when nobody is looking

`UttrflowSpeech` drives two recognisers behind one `TranscriptionBackend`: WhisperKit
(`WhisperKitBackend`) and the macOS system recogniser (`AppleSpeechBackend`). Switching between
them is a change to `EngineConfiguration` and nothing else; `SpeechEngineFactory` is the one
switch that names a concrete recogniser. This page holds the measurements and traps the code
relies on. `Docs/bakeoff.md` compares the engines; `Docs/offline.md` states the no-network rule.

## The system recogniser

- Needs no download and is faster than Whisper, but recognises 30 locales and Hindi is not
  among them, so it cannot be the product's default.
- Its `load()` downloads the locale asset when it is absent. That is a network call on the
  dictation path, the same shape as the tokenizer fetch below, and Settings compounds it by
  declaring the engine "always ready". It is left in place because the failure it produces is
  honest and recoverable (`SpeechEngineError.modelDownloadFailed` says to check the connection,
  and that fixes it). Refusing to download here without first giving Settings a way to install
  the asset, and a readiness check that consults it, would replace a slow first dictation with
  a dead end. Both of those live outside the module, so the change belongs in one piece.
- Audio is fed to the analyser in 4096-frame chunks, matching how a live microphone delivers.
- The asset check and the analyser's audio format are settled once, in `load()`, and again only
  after a transcription fails. An analyser is finished after one clip, so each piece takes a fresh
  transcriber and analyser; the next pair is built and given `prepareToAnalyze(in:)` as soon as a
  piece answers, off the wait for the words. `Docs/performance.md` has the measurement.
- The analyser has offered 16 kHz mono 16-bit on every Mac measured. When it asks for anything
  else, `AnalyserInput` converts through `AVAudioConverter`, fed in 2048-frame slices within one
  conversion so neither the converter's truncation nor its filter delay drops audio.
- Excluded from the coverage gate: it can only be exercised by real speech.

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
  kept its 200 ms either side, and came back as "nothing heard".
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
- Not yet measured against the corpus. The same padding reaches a short final piece of a long
  dictation, which is decoded alone rather than merged into the piece before it.

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
  instead: a profile that speaks only Hindi decodes every piece as Hindi, and one that speaks
  both detects every piece (`ListeningLanguages`, `Docs/early-transcription.md`). English alone
  narrows nothing, because `UserProfile.preferredLanguages` starts as English for everyone and
  pinning it would force every Hindi speaker who never opened Settings into English.
- WhisperKit re-runs detection for every fallback temperature and samples it the same way it
  samples text, top-k at that temperature. The allowed sampler ignores the temperature, so one
  window cannot change its language between retries.

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

  The 2.7x reproduces the shape the issue reported. Both alternatives are worse.

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
  re-decodes the window warmer, which is how 1.0 tokens a word still measures 2.3x. The section on
  which language the recogniser may answer in already constrains the language token for this reason;
  this is that failure measured.

- **No option measured reaches 1.3x**, and the only one whose density could — English tokens over
  Hindi audio — gets there by translating. Romanised decoding would land near it if it were
  reliable: the fixed encoder cost is most of a short dictation, so 1.99 tokens a word against
  English's 1.27 works out at about 1.2x by the step model above. It is the reliability that fails,
  not the arithmetic.

**So Devanagari stays.** The density is the tokenizer's property, not this repository's, and every
way of spending fewer steps on it changes what the speaker sees: a translation, a spelling nobody
tested, or a script that varies clip to clip. A 2.4x saving in decoder steps is real and is worth
revisiting, but only behind a decoder that writes romanised Hindi as its own output rather than one
talked into it — a different model, judged against a baseline that does not exist yet
(`Docs/measuring-accuracy.md`).

**What these numbers are not.** The clips are synthetic, and synthetic Hindi speech is not a stand-in
for a read corpus — the recorded audio `Docs/measuring-accuracy.md` calls the whole gap is still
missing, so these figures rank the options against each other and assert nothing about how well the
product hears Hindi. Word accuracy here was scored word by word against the parallel references with
a grapheme-aware split, deliberately not through `Scripts/dictation_bench.py`, whose Hindi rate is
counted over letter fragments (#705) and is therefore not a word error rate at all.

## Why one noisy clip answers differently every run

- A two-word reply mixed with brown noise at 10 dB SNR (`reply4-daniel-snr10`, "Ship it") was
  inserted as "Shit is." in 16 of 50 runs and refused as "Didn't catch that." in the other 34, on
  byte-identical audio; a second 50 split 23 to 27. Sampling in the temperature ladder is the only
  randomness in a decode, so which of the two a run gives is which draw lands.
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
- The ladder keeps the first draw that passes the thresholds and otherwise the last one
  (`Core/TranscribeTask.swift:327-405`). Every one of the 16 words came from temperature 0.8;
  0.2 to 0.6 were rejected every time, and the 34 empties are the abandoned decode at 1.0.
- **Neither a word list nor a confidence floor separates the misreading from a correct
  transcript.** Rejecting a fallback result that adds a listed word the greedy result lacks reads,
  as shipped, against a greedy result with no words in it, so it fires on the accident that the
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

## Per-word confidence

- Correction's first condition is that the recogniser was unsure. Without a per-word figure the
  condition can only be answered with a constant, which makes it either always true (the engine
  rewrites constantly) or never true (it can never fire). `RawWord.probability` comes from
  WhisperKit's `WordTiming.probability`, which is why `wordTimestamps` is asked for.
- Measured on the shipping turbo model: +4.1 ms on a 3.3 s clip and +19.1 ms on a 24.3 s one,
  0.9% and 1.4% of those transcriptions. The spread is real: "up" at 0.41 beside content words
  at 0.99 in the same sentence.
- Apple's recogniser reports nothing of the kind, so `words` is `nil` there. Absent means "not
  reported", never "all confident"; a caller that conflated the two would turn silence into
  certainty.

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
- An earlier `PromptPrefillGuard` held the end token shut for `tokens.count == prefill`, which
  is every prefill iteration *and* the first sampled token, because the token array does not
  grow while the prompt is forced — so no logits filter can tell those steps apart. WhisperKit
  0.18 ended a window on an end token sampled during its own prefill and every prompt tried
  returned an empty transcript; 1.1.0 ignores one sampled there (`Core/TextDecoder.swift:679`)
  and honours one sampled at the last prefill token, where it is a real prediction that the
  window holds no speech. The guard's only remaining effect was to suppress that prediction, so
  it is gone.
- `WhisperKitBackend` still re-runs a blank biased transcription without the vocabulary: a
  WhisperKit release or model variant that finds another way to return nothing must cost the
  user a slower dictation, never a silent one. Silence transcribes to nothing too, so this can
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
decode. Four overlapping decodes on one kit, two with a prompt and two without, returned
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
- Still seen after the fix: with 100 words, one 53-second clip's first window came back as a
  single segment with no inner timestamps, so the window ended at its fixed 30 seconds and the
  four words spoken across that boundary were lost. That is the decoder's segmentation under a
  long prompt, not the alignment.
