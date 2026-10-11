# Golden scenarios

The product is eight requirements. Each is one or more rows below, and each row is one test in
`Tests/UttrflowPipelineTests/GoldenScenarioTests.swift`, run through the real `DictationPipeline`
by the scenario driver (`ScenarioDriver.swift`). Recogniser text, word confidences and pauses are
scripted; the classifier, windowing, passes, joiner, guard and inserter are real.

## The requirements

1. A minute of speech in a SQL editor becomes the formatted statement that was said, chosen by an adapter that used a small amount of text at the caret and never a recap of dictation history.
2. "git push" is not written "gate push", decided by the previous sentence when there is one and by the person's profile when there is not.
3. Punctuation never appears where the sentence is incomplete or the mark cannot legally stand, including a stop after an incomplete clause at a piece cut.
4. Separate points become separate paragraphs or points.
5. Spoken numbers become numerals and spoken currency becomes currency.
6. The profile keeps being built from what the person does.
7. The wait feels immediate and accuracy is not traded for it.
8. Every defect is fixed at its root through one seam.

## How a row is kept

- A row that passes is a plain assertion.
- A row that fails today runs inside `withKnownIssue`, naming the open issue whose fix makes it pass. `make verify` stays green, and turns red when the fix lands without the marker being removed. The pull request that makes a row pass deletes its marker.
- A row that needs the transcription gate, the bench, the profile store or the source tree is listed in `GoldenScenarios.deferred` with its reason, and is built when its part exists.
- `GoldenScenarioDocTests` fails when a row here has neither a test nor a deferred reason, or a test has no row here.
- Line breaks are written as a return symbol; "P" is a piece and "pause" the silence before it; names are invented.

## The table

| ID | Setting | Said (pieces, pauses) | Recogniser text, scripted | Must be written | Exercises |
|---|---|---|---|---|---|
| G1.1 | Database client, empty editor, bundle id of a SQL client; object browser lists orders(id, customer_id, created_at), customers(id) | 58 s in 4 pieces, pauses 1.1, 0.9, 1.4 s: "select everything from orders", "join customers on orders dot customer id", "equals customers dot id", "where created at is after the first of january twenty twenty six" | "Select everything from orders." / "Join customers on orders dot customer ID" / "equals customers dot ID." / "Where created at is after the first of January 2026." | `SELECT *⏎FROM orders⏎JOIN customers ON orders.customer_id = customers.id⏎WHERE created_at > '2026-01-01'` with no stop, no semicolon, no capital artefact | PA.3, AD.1, AD.3, AD.6, AD.10, AD.11, AD.14, AD.19, same file: once-per-dictation, recogniser-text, date-literal, object-browser issues |
| G1.2 | Same speech, editor and browser unreadable | same | same | Same keywords and layout; unbound words stay as spoken and no identifier absent from speech and screen is written | AD.14, AD.3, CX.5 |
| G1.3 | Caret mid-statement, text before the caret `SELECT *⏎FROM orders⏎` | 6 s, 1 piece: "where status equals quote paid quote and total greater than twelve thousand" | "Where status equals quote paid quote and total greater than 12,000." | `WHERE status = 'paid' AND total > 12000`, upper-case keyword, no leading space, no stop | AD.9, AD.11, AD.12, AD.13, PN.43 |
| G1.4 | Caret after `-- ` in the same editor | 4 s: "the nightly backup finished before the migration started" | "The nightly backup finished before the migration started." | `The nightly backup finished before the migration started.` (prose in a comment stays prose) | AD.3, AD.12 |
| G1.5 | Empty editor; persona fixtures empty, SQL-heavy, prose-only; 50 earlier SQL dictations in history | the sentence of G1.4 | same | The same prose output under all three personas | same file: persona-never-selects issue, AD.2, 4.1 |
| G1.6 | Empty editor, SQL client | P1 "select id from orders where status equals quote paid quote", pause 1.2 s, P2 "and total greater than twelve thousand" | two sentences with the recogniser's stops | `SELECT id⏎FROM orders⏎WHERE status = 'paid' AND total > 12000`; identical for 200 cut positions and for one piece | same file: once-per-dictation issue, AD.40, 0.9 |
| G1.7 | Empty editor | The requirement's own sentence: "select everything from this table and join it to that table if there is this column join on it filter by date" | recogniser-style text | Per the hedge decision; invariant now: no token without a spoken source, no meant word silently lost | same file: hedge-decision issue, AD.6, CM.28 |
| G2.1 | Chat composer; text before the caret "I just committed the retry fix. "; persona developer | 2.2 s: "now I need to git push it before the demo" | "Now I need to gate push it before the demo." with gate 0.31, alternatives git, get | `Now I need to git push it before the demo.` | 1.4, 1.10, 1.11, 1.13, 1.16, RT.11 |
| G2.2 | Terminal, shell prompt only, no earlier text; persona developer | 2 s: "git push origin main" | "Get push origin main." | `git push origin main` (as spoken, no capital, no stop) | 1.3, 1.5, 1.14, 4.8, 4.9, CX.14 |
| G2.3 | Notes, no context, fresh install, no persona | "the gate push was blocked by the lock" | same, high confidence | `The gate push was blocked by the lock.` (zero false overrides) | 1.9, 1.13, 0.8, CM.33 |
| G2.4 | Notes; two dictations 3 s apart, the first ("I am about to commit this change") inserted; persona empty | second, 1.5 s: "then git push" | "Then get push." | `Then git push.` from the first sentence alone | 1.4, 1.16, RT.11, CX.10 |
| G2.5 | Terminal, persona developer, short clip | 1.2 s: "git push" | "Get push." | `git push` | AC.13, CM.14, 1.5 |
| G3.1 | Notes | P1, pause 0.9 s, P2 | "We should ship the build on Friday and then." / "Tell the team." | `We should ship the build on Friday and then tell the team.` | 2.5, 2.7, PN.1, CL.1, 2.2 |
| G3.2 | Notes | P1 ends on a comma, P2 | "I called the vendor," / "and they said no." | `I called the vendor, and they said no.` | PN.1, PN.7, 2.5 |
| G3.3 | Notes, key released mid-clause | 1 piece | "We should ship the build on Friday and then" | No stop after "then" | 2.7 |
| G3.4 | Notes, cut inside a number | P1 / P2 | "The invoice total is two thousand" / "five hundred dollars." | `The invoice total is $2,500.` | #3428, SA.13, 1.17, PN.35 |
| G3.5 | Any prose destination | 10 invented dictations, 200 random cut positions each | recogniser-style | No output contains ",." ".," ".." " ," or a stop after a colon (property) | PN.2, PN.3, PN.14 |
| G4.1 | Notes, 75 s | 6 pieces; pauses 0.5 s inside a point and 2.6 s and 2.4 s between points | six sentences about backend, design, release | Three paragraphs separated by one blank line, each ending in a stop | 2.3, PN.15, PN.16, #2102 |
| G4.2 | Chat composer where Return sends | same words | same | One insertion, no Return key sent, points on separate lines as the probe of AD.18 decides | AD.18, PN.17, IN.6 |
| G4.3 | Notes | "first fix the login bug second speed up the export third update the docs" | recogniser-style | `1. Fix the login bug⏎2. Speed up the export⏎3. Update the docs` | 2.29, 2.30 |
| G4.4 | Notes, 40 s | one point, sentences 1.0 s apart | five sentences | One paragraph (no over-segmentation) | PN.15, 2.3 |
| G5.1 | Notes | "i paid five dollars for three apples and twelve oranges" | same | `I paid $5 for 3 apples and 12 oranges.` | same file: number-default issue, PN.35, PN.30 |
| G5.2 | Notes | "the budget is two hundred fifty thousand dollars and the fee is two point five percent" | same | `The budget is $250,000 and the fee is 2.5%.` | PN.20, PN.34, PN.35 |
| G5.3 | Chat composer | "meet at six thirty and it costs three pounds fifty" | same | `Meet at 6:30 and it costs £3.50` | PN.36, PN.24 |
| G5.4 | SQL client, text before the caret `SELECT * FROM orders⏎` | "where total is greater than twelve thousand" | same | `WHERE total > 12000` (no grouping, no symbol) | AD.10, PN.43 |
| G5.5 | Notes | "no one came and one of the best was my two cents" | same | `No one came and one of the best was my two cents.` | PN.28, PN.31, PN.19 |
| G6.1 | Day 1: a terminal shows the invented tool name "Orvanta" and a dictation containing it is written. Day 2: no screen text | Day 2, 2 s: "or van ta deploy" | "Or van ta deploy." | `Orvanta deploy` | 4.1, 4.3, 4.4, LN.1, RT.5 |
| G6.2 | Secure field | any dictation | any | Nothing recorded: no history row, dictionary and persona unchanged | 4.11, RT.21, CX.23 |
| G6.3 | G6.1 then "reset profile" | Day 2 again | same | Back to `Or van ta deploy` | 4.1, 4.7, 4.10 |
| G6.4 | A correction undone twice | third dictation | same | The pairing is not applied again | 4.13, LN.10, CM.33 |
| G7.1 | 5 s dictation, reference Mac (bench) | 1 piece | scripted | Key-up to insertion within the tail target of 3.2; on the manual clock no stage waits past its budget | 3.2, SP.10, SP.16 |
| G7.2 | G1.1 as audio (gate, bench) | 58 s | real recogniser | Wait after key-up bounded by the last piece; adapter stage under 5 ms; text equals the all-at-once decode | 3.3, 0.9, SP.14, AD.10 |
| G7.3 | First dictation after launch (bench) | 3 s | real recogniser | Text appears, or the loading state is shown, within the budget of SP.3 | SP.3, SP.4, 3.8 |
| G7.4 | G1 to G5 with the rules-first path on and off | same | same | Identical outputs; corpus pass rate not lower beyond the paired bound | 3.7, 0.7, TR.20 |
| G8.1 | A fixed defect class (stop at a seam mid-clause) | 20 held-out variants, none in any code literal | scripted | All pass | 2.5, OP.2 |
| G8.2 | G3.1, G5.1, G1.3 | rules path and model path | scripted | Same written output on both | 2.36, MD.1 |
| G8.3 | Source tree | n/a | n/a | No literal of three or more words equals a corpus phrase; closed-list count not above baseline | same file: closed-list audit issue, OP.4 |
