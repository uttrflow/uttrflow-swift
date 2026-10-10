# What the unified log may carry

Uttrflow writes to the unified log with `Logger` under the subsystem `com.uttrflow.Uttrflow`,
one category per area (`account`, `clipboard`, `launch` and others). Anybody who can read this
Mac's log can read those messages, and a message marked `privacy: .public` also travels
unredacted in anything that collects logs, such as a sysdiagnose. This page states what a
message may carry and how `Scripts/log_privacy_audit.py` enforces it.

## The rule

**No log message carries text a person typed, read, said or was offered.** That covers the
focused field's line and value, a suggestion's candidates and completions, an accepted
completion, a prompt, a transcript, what was heard, a clip, a dictionary word or snippet, and
another application's window title or document name.

A message carries the shape of that text instead: its length in characters, a count, whether
it is present, and the reason, route, engine or timing that explains what happened.

Swapping `.public` for `.private` is not a fix. A private value is still captured, and a Mac
configured to reveal private data shows it in clear. The text is left out altogether.

Suggestion logs hide the front application's name and bundle identifier as `private` by
default. Set `UTTRFLOW_DEBUG_SUGGESTION_APPLICATIONS=1` in the app's environment to include
application identities during local debugging.

An error from a model or a third-party framework is logged by its type and case
(`ErrorLog.failure`), because its payload may hold the text the model was given or wrote.

## Tab-to-complete

`Sources/Uttrflow/Suggestion/SuggestionLog.swift` builds the predict lines that describe the
typed line, and `SuggestionLogTests` checks each one against invented text; `TURN` and
`CONTEXT` are written inline in `SuggestionCoordinator.swift` and log lengths only. The keys are:

| Line | Carries |
|---|---|
| `FIELD_READ` | whether the field read was attempted, elapsed time, whether it succeeded, and the front application's identity only when the debug switch is enabled |
| `TURN` | the front application's identity only when the debug switch is enabled, whether the field was read, `lineChars`, whether it has a value and the value's length in UTF-16 `units`, the selection's location, whether a caret was read, the role, `labelChars`, whether the field has an identifier, whether it is secure, placement |
| `QUERY` | `typedChars`, how many candidates the corpus held, whether the model is ready |
| `OPTIONS` | `typedChars`, and `none` or how many values the machine offers |
| `QUIET` | `typedChars`, the silence's reason, rejections, whether the field is silenced, whether suggestions are on |
| `GENERATE` | the application name only when the debug switch is enabled, `typedChars`, how many lines, elapsed time, `firstChars` |
| `ALTERNATIVES` | `typedChars`, how many lines, elapsed time |
| `ATTEST` | `typedChars`, lines in, lines out, how many were dropped |
| `VERIFY` | `typedChars`, candidates in and out, elapsed time, `firstChars` |
| `ACCEPT` | the completion's `chars`, `typedChars`, the insertion route |
| `CONTEXT` | the lengths of the window title, the surroundings and the preceding text, and how many recent lines |
| `STALL` | the step the turn left behind was waiting on, the application's bundle identifier only when the debug switch is enabled, and how many seconds it waited |

A failed `GENERATE` or `ALTERNATIVES` pass carries `typedChars` and the error as
`ErrorLog.failure` renders it.

A run is followed by these sizes and by the order of the lines, which is enough for
`Scripts/e2e_predict.sh`: it types text it chose, so it knows the length to expect.

## Sign-in and the session

`HTTPAuthenticationService` (`Sources/UttrflowAccount/HTTPAuthenticationService.swift`) and the
keychain token store (`TokenStore+Keychain.swift`) log each step under the category `account`,
by provider, method, port, HTTP status and a fixed failure reason alone. No token, code, state,
email address or name is logged.

| Line | Says |
|---|---|
| `sign-in: started provider=P` | sign-in began with provider P |
| `sign-in: waiting on loopback port N` | the browser was given a page that comes back to port N (`method=browser`) |
| `sign-in: no loopback port, signing in by code instead` | no port bound, so the device code is shown (`method=code`) |
| `sign-in: the browser came back, exchanging the code` | the redirect reached the port |
| `sign-in: token exchange answered N` | `POST /v1/auth/token` answered N |
| `session: token kept in the data-protection keychain` or `file-based keychain` | which keychain took the refresh token |
| `session: neither keychain took the token` | no keychain took it; sign-in then fails with `reason=sessionCouldNotBeKept` |
| `sign-in: session kept, reading the profile` | the tokens are stored and the first `GET /v1/me` follows |
| `sign-in: profile answered N` | the first `GET /v1/me` answered N |
| `profile refused: unsigned, wrongly signed or inconsistent` | the entitlement did not verify |
| `session: refresh answered status=N` | `POST /v1/auth/refresh` answered N; 401 signs this Mac out |
| `session: refresh failed reason=R` | the refresh failed, with a fixed reason such as `serverUnreachable` |
| `session: profile answered N` | a later `GET /v1/me` answered N; 304 means unchanged |
| `sign-out: started`, `sign-out: completed` | the session on this Mac is being, and has been, removed |

## How it is enforced

`Scripts/log_privacy_audit.py` runs in `make verify` (`make log-audit`). It reads every
interpolation inside a `Logger` call in `Sources/`, and every interpolation in a file whose
name ends in `Log.swift`, and fails when the interpolated value still names user text —
`typed`, `text`, `line`, `value`, `candidate`, `completion`, `prompt`, `transcript`, `spoken`,
`heard`, `clip` and the rest of its `USER_TEXT` list — once `.count`, `.isEmpty`, `== nil` and
`!= nil` are taken out. It fails whatever the privacy level.

It also fails when a message publishes a description: `String(describing:)`,
`String(reflecting:)`, `.localizedDescription`, `.description`, `.debugDescription`, or a bare value named like an
error or a failure, at every privacy level, including `.private` — a private value is still
captured, so marking a description private is not a fix, only a narrower leak. An error's
description can carry its payload — a database path under the home folder, a raw SQLite
message, the text a model was given — so an error is logged by `ErrorLog.failure`, which
keeps its type and case. A description of a value whose every case is fixed wording goes on the
audit's second list with its reason, printed on every run. `--self-test`, which `make
verify` passes, proves the audit still reports each kind of violation it looks for.

A value that matches a name and carries no user text goes on the audit's allow-list with its
reason, and the list is printed on every run. A call to a builder in a `Log.swift` file is
trusted at the call site because the builder's own file is scanned whole.

Both lists are keyed on the exact interpolation a log message carries, and the audit refuses to
report anything at all while an entry names a file that is gone, or an interpolation that file no
longer carries. An exception it cannot check is not one it has checked, and printing it beside a
clean scan would claim a privacy decision nobody made; it would also let the same expression come
back later and inherit the old exemption. So delete the entry with the log call, or point it at
the interpolation the message carries and decide afresh. The match is parser-aware: the same
text in a comment or in an ordinary string does not keep an entry alive.

The audit reads names, not types, so it is a tripwire rather than a proof: a value called
something innocent can still carry text. Keep user text out of names like `message` and pass
it to a builder instead.

Related: [crash-reporting.md](crash-reporting.md), [predict.md](predict.md),
[account-session.md](account-session.md).
