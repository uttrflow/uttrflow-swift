# Operator runbook

Four things V2 needs that no amount of code can supply: credentials, a bucket, a voice,
and a signing identity. Everything around each of them is built and tested — each is a
configuration step, not a development one.

They are independent. Do them in whatever order suits you, or none of them: the app runs
locally today without any of it, because every provider falls back to a development stub
that walks the identical path.

---

## 1 · Sign-in credentials

**Blocks:** signing in with a real account. **Not blocked:** everything else — an
unconfigured provider is replaced by a development stub, and `/v1/health` reports
`signInIsStubbed: true` so you can never mistake one for the other.

You need six values, three of them optional if you drop Apple:

| Variable | Where it comes from |
|---|---|
| `GOOGLE_CLIENT_ID` / `_SECRET` | Cloud Console → APIs & Services → Credentials → OAuth client ID → **Web application** |
| `GITHUB_CLIENT_ID` / `_SECRET` | GitHub → Settings → Developer settings → OAuth Apps |
| `APPLE_CLIENT_ID` | A **Services ID**, not the bundle identifier |
| `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` | Apple Developer → Keys. The private key is the base64 of the `.p8` |

Each provider needs `${PUBLIC_BASE_URL}/v1/auth/<provider>/callback` registered as an
authorised redirect URI, matching exactly.

Run `npm run keygen` in `uttrflow-backend` for the three it generates rather than
obtains — `ENTITLEMENT_SIGNING_KEY`, `SESSION_SIGNING_KEY`, `ADMIN_TOKEN`. It prints them
and writes nothing.

**Then one thing in the app**, and it is release-blocking: put the 32 raw public-key bytes
into `Ed25519EntitlementVerifier.releasePublicKeyBytes`, which is empty today. It fails
closed, so a build shipped without it signs nobody in — which is the safe direction, and
deliberate. **Do not fill it with zeroes.** An all-zero Ed25519 key is a small-order point
that CryptoKit verifies without the cofactor: measured here, an all-zero signature
verified against it for 491 of 2000 messages. Anyone could grant themselves Pro. A test
asserts the trap is real so nobody "fixes" the empty constant that way.

---

## 2 · The corpus bucket

**Blocks:** pulling and uploading evaluation samples. **Not blocked:** the app, at all —
the harness is not linked into it and cannot be.

Set `CORPUS_BUCKET` and `AWS_REGION`. The IAM grant needs `s3:GetObject` **and**
`s3:PutObject` — the upload path is new. Without them the backend still runs: download
URLs point at an endpoint returning 501 that names what is missing, rather than a broken
URL.

---

## 3 · The recordings

**Blocks:** any accuracy number, and therefore the correction feature's regression gate.
Nothing else.

About a thousand samples, roughly sixteen hours. Read them in sittings:

```bash
uttrflow-eval record --backend <url> --cohort naveen-quiet --sync
```

It is resumable, so stopping after twenty passages leaves the rest. **The local write is
the commit** — audio is saved to disk before it is offered to the backend, so a crash or
dead Wi-Fi costs an upload and never a take. Failed uploads retry next sitting.

Slug validity is checked before you speak, because a name Postgres refuses discovered
after forty passages is discovered too late.

Then, unattended:

```bash
uttrflow-eval transcribe --from-catalogue --save-baseline
```

Results are never pooled into one number: by language, by stressor, by cohort. Any slice
going backwards counts as a regression even when the headline improves — an engine that
gets better at English and worse at Hinglish has not got better.

---

## 4 · Notarisation

**Blocks:** giving the app to anyone else. **Not blocked:** running it yourself,
indefinitely, with the permissions you have already granted.

Needs the Apple Developer Programme, $99/year. Then:

```bash
xcrun notarytool store-credentials uttrflow-notary --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PASSWORD
make app-dist IDENTITY="Developer ID Application: NAME (TEAMID)"
make notarise
```

`make notarise-check` runs every preflight today, with no account, so you find out now
rather than after enrolling.

---

## Also outstanding, and smaller

**Provider brand marks.** Fetched, never committed — they are other people's trademarks
and this repository is public:

```bash
./Scripts/fetch-provider-marks.sh
```

That places Google's four-colour G at `Sources/Uttrflow/Resources/GoogleMark.png`, which
`.gitignore` keeps out of the repository. Shipping the mark inside an app that implements
Google Sign-In is what Google publishes it for; redistributing it in public source is a
different act, and not one the asset terms clearly allow.

Both providers forbid redrawing their mark, so nothing is approximated and no `Path`
version exists. A build that skips the script is fine and is what CI-less contributors
get: `ProviderMark` renders nothing, and the button carries its wording alone, which is
what the GitHub button does in every build. GitHub's Invertocat is not fetched
automatically — its pack is a designed set rather than a predictable archive.

`Scripts/bundle.sh` needs no change; `.process("Resources")` already seals whatever is
there into `Contents/Resources`.

**A decision, not a task.** Onboarding currently puts sign-in *before* welcome, taking
"the first thing anyone sees" literally. Pitching before charging is usually better.
Swapping them is two lines in `OnboardingStep.position`.
