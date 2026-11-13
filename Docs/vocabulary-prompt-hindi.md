# The vocabulary prompt on Hindi speech

`VocabularyPrompt` wraps the dictionary's words in an English sentence, " The words used here are
… and the rest of what was said is in the usual lower case.", whatever the language hint
([speech-vocabulary-prompt.md](speech-vocabulary-prompt.md)). Whisper reads the prompt as the
transcript before the audio, so on Hindi speech that English sentence and the Latin spellings
inside it may pull the decoder out of Devanagari. This page measures it.

## How it was measured

`uttrflow-eval vocabulary-prompt` has the hi-IN `say` voice Lekha read twelve invented sentences
(`VocabularyPromptCorpus`): eight in Hindi and four code-mixed with English words, each holding
names no recogniser was trained on. Every clip is decoded under the Hindi hint and with no hint,
in four prompt conditions:

| Condition | What the recogniser is handed |
|---|---|
| `none` | no prompt |
| `latinFrame` | today's frame around the names as a dictionary types them (`Varikesh`) |
| `devanagariFrame` | the same frame around the names in Devanagari (`वरीकेश`) |
| `wordsOnly` | the Devanagari names alone, as the text before the caret, which carries no frame |

`VocabularyPromptRow` scores each transcript: the share of its letters in Devanagari, whether it
left Devanagari (under a fifth of its letters), how many names it holds in either script, and
its word error rate against the Devanagari sentence. Accuracy only: no timing is recorded here,
since the measuring machine is a virtual one.

```bash
uttrflow-dev models install
uttrflow-eval vocabulary-prompt        # writes .uttrflow-eval/vocabulary-prompt-rows.tsv
```

## Result

WhisperKit `openai_whisper-large-v3-v20240930_turbo_632MB`, weights
`0f63a7800b00dd0226abd051b906c246e1907482`, macOS 26.6.2 (25G83), voice Lekha. Apple's speech
engine: not measured.

| Hint | Prompt | Clips | Left Devanagari | Devanagari share | Names heard | Word error rate |
|---|---|---|---|---|---|---|
| auto | none | 12 | 0 | 100.0% | 4/13 | 29.4% |
| auto | latinFrame | 12 | 6 | 33.7% | 9/13 | 76.5% |
| auto | devanagariFrame | 12 | 0 | 100.0% | 13/13 | 11.8% |
| auto | wordsOnly | 12 | 0 | 100.0% | 11/13 | 14.7% |
| hi | none | 12 | 0 | 100.0% | 4/13 | 29.4% |
| hi | latinFrame | 12 | 6 | 33.7% | 9/13 | 76.5% |
| hi | devanagariFrame | 12 | 0 | 100.0% | 13/13 | 11.8% |
| hi | wordsOnly | 12 | 0 | 100.0% | 11/13 | 14.7% |

- **Today's frame is the worst condition on Hindi speech.** With the names in Latin letters, half
  the clips leave Devanagari and the word error rate is two and a half times that of no prompt.
  The clips that leave go three ways: romanised Hindi ("Saayank ji abhi ghar pard nahi hai"),
  English ("Tolanshi has made food"), or the frame itself ("or the rest of what was said,").
- **The same frame with Devanagari names is the best.** Every clip stays in Devanagari, every name
  is heard, and the word error rate falls from 29.4% with no prompt to 11.8%.
- **The frame is not what does the harm.** The names alone, with no frame, keep the script and hear
  11 of 13 names; it is the Latin spellings that pull the decoder out of Devanagari.
- **The hint changes nothing here.** Under the Hindi hint and with none, every transcript is
  identical: on this voice Whisper detects Hindi by itself.

What this leaves open: the dictionary holds Latin spellings, so a Devanagari prompt needs each
name's Devanagari form, and English speech must keep today's prompt byte for byte. Both belong to
the change this measurement argues for, not to this page.
