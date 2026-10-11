<!--
Thank you. A few things that make review quick — none of them are forms to fill in for
their own sake, and if one does not apply to your change, delete it.
-->

## What this changes, and why

<!-- The why matters more. If you tried an obvious approach first and it did not work,
that is the most useful sentence you can write here — it stops the reviewer proposing it. -->

## How you know it works

<!-- Which test covers it, or what you did by hand and what you saw. -->

For changes to `Sources/UttrflowAI/PromptBuilder.swift` or the rules, include the
`make bakeoff ARGS="--against <saved-result.json>"` comparison output, or explain why a
corpus comparison could not be run. `Docs/measure-a-change.md` says which command a change needs.

For a change to prompts or guards in `Sources/UttrflowAI`: the `*LiveModelTests` result from a Mac
with Apple Intelligence, with `PromptBuilder.version` and the macOS build. `make verify` prints
`live-model tests: N run, M skipped`; a skipped suite proves nothing.

For a change to `technical-lexicon.json`: the corpus slice it affects, and its bench before and after ([guide](../Docs/lexicon.md)): <!-- slice, or why none -->

For a change to `weightsRevision`, `tokenizerRevision` or the `WhisperKit` version: the
`make accuracy-gate` output, and the new baseline it asks for ([steps](../Docs/speech-model-install.md#pinned-model-files)).

For a fix to a wrong dictation: corpus case added (fails before, passes after): <!-- case id, or why none can exist -->

---

- [ ] `make verify` passes locally (lint, PII audit, build, tests, coverage floor, offline audit)
- [ ] New behaviour has a test, or there is a reason in the PR why it cannot
- [ ] No real email address, postal address or personal data in fixtures — `example.com` and invented streets
- [ ] Comments are one line, present tense, and describe what the code does now
- [ ] A latency claim says where its clock starts and stops ([rules](../Docs/agents/code-quality.md#measurements-and-thresholds))

If this change stores anything learned about the person, answer each of these and update
[`Docs/persona-threat-model.md`](../Docs/persona-threat-model.md) in this pull request:

- [ ] Where it is stored, encrypted or not, and with what file permissions
- [ ] How it is reset, and that reset personalisation clears it
- [ ] Whether it is in the export archive and in retention
- [ ] What a log line or crash report could reveal about it
- [ ] What the settings screen shows of it

If this change adds or changes a screen, a settings page or a report view, answer each of these
(see [`Docs/accessibility-controls.md`](../Docs/accessibility-controls.md) and
[`Docs/ui-tests.md`](../Docs/ui-tests.md)):

- [ ] Every control has an accessible label and role; each list item is one accessibility element with edit and remove as named actions
- [ ] Every action works from the keyboard alone, including a destructive one and its confirmation
- [ ] No information is carried by colour alone, and `make design-audit` passes with the new view covered
- [ ] The layout holds at the largest text size and under Reduce Motion
- [ ] `make accessibility-controls` lists every new control

Add a reason only when it changes what a reader should do. Put durable measurements or
architectural rationale in `Docs/`; put development history in this description or the commit.

<!--
If this is a draft or an idea you want a view on before finishing, open it as a draft and
say so. That is welcome and is cheaper than building the wrong thing.
-->
