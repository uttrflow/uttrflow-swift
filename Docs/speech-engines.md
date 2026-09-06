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
  `Int(448 / 2)` (WhisperKit 0.18, `Core/TextDecoder.swift:339` and `Core/Models.swift:1420`).
  It keeps the *last* 111 tokens and drops the rest without a word, so a best-first vocabulary
  would lose precisely the words worth having; the prompt is packed word by word here instead,
  skipping a word that does not fit rather than stopping.
- The prompt is applied once ahead of the prefill and re-forced for every 30-second window:
  WhisperKit builds the decoder's initial prompt before its seek loop and never overwrites it.
- The empty vocabulary, an absent tokeniser, or a prompt nothing survives leaves the decoding
  options untouched. A word missing from the prompt costs the user a correction; a dictation
  refused because a word would not encode costs them the dictation.

## The prefill guard

- WhisperKit ends a window as soon as its sampler predicts the end token, and it applies that
  test on every iteration of the decode loop, including the ones that are force-feeding the
  prompt and discarding whatever the sampler said. Asked to transcribe five seconds of clear
  speech with a prompt, it returned an empty string for every prompt tried: three words, one
  word, a comma-separated glossary, a sentence of prose, at nine tokens and at fifty-two.
- `PromptPrefillGuard` holds the end token shut until the forced prefill
  (`[<|startofprev|>] + prompt + [<|startoftranscript|>, language, task, timestamps]`, minus
  language and task for an English-only model; `Core/TextDecoder.swift:313-342`) has gone
  through. The `tokens.count == sampleBegin` shape is WhisperKit's own (`SuppressBlankFilter` is
  built the same way) and works because the token array does not grow while the prompt is
  forced. It is installed through `logitsFilters`, a documented extension point, and reassigned
  on every call so a guard never outlives the prompt it was measured for.
- Delete it when WhisperKit stops ending a window during its own prefill. Until then
  `WhisperKitBackend` also re-runs a blank biased transcription without the vocabulary: a
  WhisperKit release or model variant that finds another way to return nothing must cost the
  user a slower dictation, never a silent one. Silence transcribes to nothing too, so this can
  decode twice for no gain, which is the right price.
