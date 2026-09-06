# Security

## Reporting a vulnerability

**Please do not open a public issue.** Use GitHub's private reporting:

**[Report a vulnerability](https://github.com/uttrflow/uttrflow-swift/security/advisories/new)**

That reaches the maintainer privately and gives us somewhere to talk before anything is
public. It needs a GitHub account, which for a code repository is a fair ask; if that is a
problem for you, open a normal issue saying only *"I have a security report and no GitHub
account"* — with no detail in it — and you will be given another way.

Please include what you did, what happened, and what you expected. A proof of concept
helps enormously. You will get an acknowledgement within a few days; this is a small
project with one maintainer, so please be patient rather than assuming silence is a
brush-off.

## What is in scope

This repository is the macOS app. The parts worth looking at hardest:

- **The offline promise.** Dictation must never touch the network once the speech model is
  on disk, and the clipboard, history, dictionary and snippets must never leave the Mac.
  Anything that breaks that is a security bug even if nothing is exploitable, because it is
  the claim the product is sold on. `Scripts/offline_audit.sh` asserts the structure this
  rests on.
- **Entitlement verification.** `Ed25519EntitlementVerifier` decides what a build believes
  about a subscription. A way to make it accept something the backend did not sign is the
  most serious class of bug here.
- **The update path.** Sparkle checks an EdDSA signature against a public key compiled into
  the app. A way to get an unsigned or differently-signed archive installed is critical.
- **Text insertion.** The app types into other applications through the Accessibility API.
  Anything that lets content it handles execute rather than be typed matters.
- **Secret detection in the clipboard.** Failing to mark something as a secret is a bug;
  it is not a vulnerability in this app, because the clip was already on the clipboard.

## What is not

- The backend service is a separate, closed codebase. Report issues in it to the same
  address, but they are not fixable from here.
- `SUPublicEDKey` and `Ed25519EntitlementVerifier.releasePublicKeyBase64` are **public
  halves** and are in the source on purpose. Publishing them is how a build can be checked
  against the deployment it was made for.
- Test fixtures that look like credentials — `SecretDetectionTests` is full of them — are
  invented, and exist because recognising that shape is what the clipboard does.

## Supported versions

The latest release. This is a small project; there is no back-porting, and a fix ships in
the next release rather than as a patch to an old one.

## What runs automatically

So you know what has already been looked at before you spend time on it:

| Check | When | What it is for |
|---|---|---|
| `make verify` | Every PR, every push to `main`, every release tag | Lint, PII audit, full build, 4,000+ tests, 95% per-module coverage floor, offline audit |
| **CodeQL** (`security-and-quality`) | Weekly | Static analysis of Swift for security defects — the whole-call-path kind a reviewer misses. Weekly rather than per-PR: Swift analysis needs a build CodeQL runs under Rosetta, and two forty-minute macOS jobs a pull request is more than five concurrent runners can deliver |
| **Dependency review** | Every PR | Refuses a new dependency with a known vulnerability, or a licence we cannot ship |
| **Dependabot** | Weekly | Updates actions and Swift packages as pull requests, which go through the same gate as anything else |
| **Secret scanning + push protection** | Every push | Blocks a push containing something credential-shaped, before it is public |
| **OpenSSF Scorecard** | Weekly, and on protection changes | An outside opinion on supply-chain posture; results land in the Security tab |

Workflow actions are **pinned to commit SHAs**, not to mutable tags, so a compromised tag
on a third-party action cannot change what runs here. Dependabot updates the pins.

`main` is protected by a ruleset: no direct pushes, no force-pushes, no deletion, and a
reviewed pull request for every change.
