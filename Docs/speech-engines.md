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
