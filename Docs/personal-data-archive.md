# Personal data archive

Settings → Dictation offers "Export personal data" and "Import personal data", which move the
personal dictionary and snippets between profiles or Macs as one versioned JSON file. The
format is `PersonalDataArchive` (`Sources/UttrflowAI/PersonalDataArchive.swift`), the import is
`PersonalDataTransfer.importArchive` (`Sources/UttrflowAI/PersonalDataTransfer.swift`), and
`AppDelegate` drives the save and open panels. The archive is created only after the user
chooses a destination; import reads only the file the user chooses. There is no sync or
automatic upload.

## What the file holds

Dictionary spellings and pronunciations, their origin and usage counters, snippet triggers
and expansion text, and their dates and usage counters. The export is not encrypted, and anyone who can read the chosen
file can read its contents. Before choosing a destination, the user can omit snippets whose
trigger or expansion matches the credential recogniser, or include every snippet; the recogniser
covers known credential shapes and cannot identify every private phrase. Uttrflow creates an
owner-only sibling file (`PrivateFile.fileMode`) before writing archive bytes, then atomically
replaces the chosen destination.

## How an import is applied

Import validates the complete archive before writing either store. It merges by
case-insensitive dictionary spelling and normalised snippet trigger, keeps existing entries
when they collide, and reports how many duplicates it skipped. A malformed or unsupported
archive is refused without changing either list, and so is an import that would leave more
than `PersonalDictionaryStore.maximumInferredEntries` (256) inferred words in the dictionary.

Selected files are read in bounded chunks and refused above 5 MiB before JSON decoding. An
archive may contain at most 1,000 snippets; each trigger is limited to 256 UTF-8 bytes and each
expansion to 16 KiB. Dictionary spellings and pronunciations are each limited to 256 UTF-8
bytes. These limits are checked before either store changes, and their refusal is reported in
the import alert.

## Versions

The archive schema is `PersonalDataArchive.currentVersion` (1). An incompatible format gets a
new version rather than a reader that guesses at fields; a file of any other version is refused.

## Related pages

- `Docs/app-dictionary-store.md` — the dictionary store and its inferred-word cap.
- `Docs/ai-snippet-store.md` — the snippet store.
