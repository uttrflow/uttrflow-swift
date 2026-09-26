# Uttrflow — developer entry points.
#
# Every target here is what CI runs, so "green locally" and "green in CI" cannot
# diverge. Xcode supplies the toolchain; the build itself is Swift Package Manager.

export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

SWIFT := xcrun swift
SOURCES := Sources Tests UITests

.DEFAULT_GOAL := verify

.PHONY: build
build: ## Compile every module.
	$(SWIFT) build

.PHONY: test
test: ## Run the test suite.
	$(SWIFT) test

.PHONY: coverage
coverage: ## Run tests and enforce the per-module coverage floor.
	./Scripts/coverage.sh

.PHONY: format
format: ## Rewrite sources in canonical style.
	xcrun swift-format format --in-place --recursive --configuration .swift-format $(SOURCES)

.PHONY: lint
lint: ## Fail on any style or documentation violation.
	xcrun swift-format lint --strict --recursive --configuration .swift-format $(SOURCES)

.PHONY: offline-audit
offline-audit: ## Prove the dictation path still cannot reach the network.
	./Scripts/offline_audit.sh

.PHONY: offline-audit-tokenizer-test
offline-audit-tokenizer-test: ## Prove the offline audit fails, not notes, a missing tokenizerFolder pin. Needs no build.
	./Scripts/offline_audit_tokenizer_test.sh

.PHONY: comment-audit
comment-audit: ## Prove no file gained a multi-line comment. Needs no build.
	@python3 Scripts/comment_audit.py

.PHONY: comment-report
comment-report: ## List the multi-line comments left, worst file first.
	@python3 Scripts/comment_audit.py --report

.PHONY: match-audit
match-audit: ## Prove no source file gained a word match decided by shape. Needs no build.
	@python3 Scripts/loose_match_audit.py

.PHONY: match-report
match-report: ## List the word matches still decided by shape, with the line.
	@python3 Scripts/loose_match_audit.py --report

.PHONY: ratchet-test
ratchet-test: ## Prove the comment and word-match baselines refuse a rise without --after-merge. Needs no build.
	@python3 Scripts/audit_ratchet_test.py

.PHONY: range-test
range-test: ## Prove the disclosure audit reads every revision range the pre-push hook hands it. Needs no build.
	@python3 Scripts/disclosure_range_test.py

.PHONY: hits-test
hits-test: ## Prove the disclosure audit counts every same-line match, not just the first per pattern. Needs no build.
	@python3 Scripts/disclosure_hits_test.py

.PHONY: pre-push-test
pre-push-test: ## Prove the pre-push hook uses the disclosure audit paired with the hook, not the worktree's copy. Needs no build.
	@python3 Scripts/pre_push_hook_test.py

.PHONY: update-feed-test
update-feed-test: ## Prove the release scripts parse update-feed URLs by host, not prefix.
	@python3 Scripts/update_feed_gate_test.py

.PHONY: entitlement-gate-test
entitlement-gate-test: ## Prove the release gates read entitlement Boolean values, not just key names.
	@python3 Scripts/entitlement_gate_test.py

.PHONY: issue-template-audit
issue-template-audit: ## Refuse a public issue template that prompts for content the disclosure rule forbids. Needs no build.
	@python3 Scripts/issue_template_audit.py

.PHONY: issue-template-test
issue-template-test: ## Prove the issue template audit catches the bug it was written for. Needs no build.
	@python3 Scripts/issue_template_audit_test.py

.PHONY: store-permissions
store-permissions: ## Prove nothing writes a local store's files except through PrivateFile. Needs no build.
	@python3 Scripts/store_permissions_audit.py

.PHONY: uitest-arguments
uitest-arguments: ## Prove the UI harness refuses a rounds count it cannot run. Compiles it; needs no screen.
	@python3 Scripts/uitest_arguments_test.py

.PHONY: uitest-result-path
uitest-result-path: ## Prove a second `make uitest` moves the prior result bundle aside. Needs no screen.
	@python3 Scripts/uitest_result_path_test.py

.PHONY: hook-test
hook-test: ## Prove the commit-msg hook refuses a message for the reason it actually has. Needs no build.
	@python3 Scripts/commit_msg_hook_test.py

.PHONY: exclusion-audit
exclusion-audit: ## Prove every coverage exclusion is in the tree and small enough to review by reading. Needs no build.
	@python3 Scripts/coverage_report.py --check-exclusions --self-test

.PHONY: bundle-test
bundle-test: ## Prove the bundle's resource-bundle check still fails on a bundle that was not copied. Needs no build.
	./Scripts/bundle.sh --self-test

.PHONY: offline-test
offline-test: ## Prove the offline audit still refuses every way of reaching the network. Needs no build.
	@python3 Scripts/offline_audit_test.py

.PHONY: docs-audit
docs-audit: ## Prove the documentation still describes this tree, including that CLAUDE.md delegates to AGENTS.md. Needs no build.
	./Scripts/docs_audit.sh --self-test

.PHONY: pii-audit
pii-audit: ## Prove no personal data is in the tree. Needs no build.
	./Scripts/pii_audit.sh

.PHONY: log-audit
log-audit: ## Prove no log message carries text a person typed, read or said. Needs no build.
	@python3 Scripts/log_privacy_audit.py --self-test

.PHONY: perf-budget
perf-budget: ## Prove the source keeps to the energy and memory budget, and that each check still bites. No build.
	@python3 Scripts/perf_budget_audit.py --self-test

# Needs the speech model and the suggestion model on disk, so it runs on a Mac rather than in CI.
.PHONY: perf-budget-models
perf-budget-models: ## Fail when the model harness reads memory over the budget. Needs both models installed.
	$(MAKE) bakeoff ARGS="gpu-memory --passes 12 --release"
	$(MAKE) bakeoff ARGS="profile --dictations 10"

.PHONY: pasteboard-audit
pasteboard-audit: ## Prove only the clipboard adapters touch NSPasteboard. Needs no build.
	./Scripts/pasteboard_audit.sh

.PHONY: release-tag-test
release-tag-test: ## Prove release tags come from main. Needs no build.
	./Scripts/release_tag_ancestry_test.sh

.PHONY: provider-mark-test
provider-mark-test: ## Prove the Google mark selector recognises both the legacy and current archive layouts. Needs no build.
	./Scripts/select_google_mark_test.sh

.PHONY: release-order-test
release-order-test: ## Prove `make release` keeps its stages in order under -j. Dry-run only.
	./Scripts/release_order_test.sh

.PHONY: soak-test
soak-test: ## Prove soak.sh's growth report compares the union of two snapshots. Needs no build.
	./Scripts/soak_test.sh

.PHONY: e2e-predict-cleanup-test
e2e-predict-cleanup-test: ## Prove the live prediction harness removes its scratch directory and helper on exit. Needs no build.
	./Scripts/e2e_predict_cleanup_test.sh

.PHONY: publish-resume-test
publish-resume-test: ## Prove a rerun after release creation resumes the feed update instead of failing or duplicating. Needs no build.
	./Scripts/publish_resume_test.sh

.PHONY: publish-cleanup-test
publish-cleanup-test: ## Prove publish.sh leaves no release-sized temp file behind. Needs no build.
	./Scripts/publish_cleanup_test.sh

.PHONY: bundle-requirement-test
bundle-requirement-test: ## Prove every bundle-signing mode has a designated requirement. Needs no build.
	./Scripts/bundle.sh --requirement-self-test

.PHONY: disclosure-audit
disclosure-audit: ## Prove nothing private to building this reached the tree. No build.
	@python3 Scripts/disclosure_audit.py

.PHONY: disclosure-history
disclosure-history: ## Scan every commit on every ref. Run before a repo goes public.
	@python3 Scripts/disclosure_audit.py --history

# `pii-audit` first, and `offline-audit` last, for opposite reasons.
#
# The PII audit reads source and nothing else, so it costs two seconds. Putting it ahead
# of the build is what makes it useful: somebody who has pasted a real address into a
# fixture is told before a five-minute build, not after one, and a check people wait
# through is a check they learn to skip. It is also the only step here whose failure
# cannot be fixed after the fact — this repository is going public, and a published
# address stays published.
#
# `offline-test` sits with the other no-build checks, ahead of the build, and is what
# stops `offline-audit` narrowing again: the audit's own failure was that it passed while
# looking at seven modules out of twenty-four, and a gate cannot report that about itself.
#
# `offline-audit` last, because it reads the built object files and so needs `build` to
# have run. It is in the gate rather than beside it because it had drifted for weeks
# without anybody noticing: a check nothing runs is a check that is already wrong, and
# this one polices the claim the whole product is sold on.
# `disclosure-audit` sits beside `pii-audit`, at the front, for the identical reason: it
# reads text and nothing else, so it costs two seconds, and it is the other check here
# whose failure cannot be fixed after the fact. A competitor's name in a commit is
# published the moment the commit is, and no later edit reaches a clone or a cache.
.PHONY: verify
verify: pii-audit disclosure-audit issue-template-audit docs-audit comment-audit match-audit ratchet-test range-test hits-test hook-test pre-push-test update-feed-test entitlement-gate-test issue-template-test uitest-arguments uitest-result-path log-audit store-permissions pasteboard-audit bundle-requirement-test bundle-test release-tag-test provider-mark-test release-order-test soak-test e2e-predict-cleanup-test publish-resume-test publish-cleanup-test offline-audit-tokenizer-test offline-test exclusion-audit perf-budget lint build coverage offline-audit ## The whole gate: PII, disclosure, issue template prompts, docs, comments, word matches, log privacy, clipboard, bundle signing, packaging checks, release tags, release stage order, soak growth-report parsing, publish resumability, publish cleanup, offline tokenizer gate, coverage exclusions, energy and memory budget, lint, build, tests, coverage floor, offline audit.

# Hooks are not cloned — .git/hooks is local to a checkout — so this points git at a
# directory that is. One command per clone, and the gate cannot be forgotten after that.
.PHONY: hooks
hooks: ## Install the commit-msg and pre-push gates.
	@git config core.hooksPath .githooks
	@echo "Hooks installed:"
	@echo "  commit-msg  reads every commit message"
	@echo "  pre-push    reads every commit being pushed, to any branch,"
	@echo "              and runs 'make verify' before a push to main"
	@echo "Skip deliberately with: git commit --no-verify / git push --no-verify"

.PHONY: soak
soak: ## Watch a running Uttrflow's heap for the growth #140 unwinds. Hours, not minutes.
	./Scripts/soak.sh

.PHONY: uitest
uitest: ## Drive dist/Uttrflow.app through the UI suite. Needs a windowing session, not CI.
	./Scripts/uitest.sh

.PHONY: app
app: ## Build and sign Uttrflow.app into dist/ for this Mac.
	./Scripts/bundle.sh

# Its own identifier, so it runs beside the installed app and keeps its own settings,
# stores and permission grants. Docs/development-build.md says what that costs.
.PHONY: app-dev
app-dev: ## Build Uttrflow-Dev.app into dist/, which runs beside the installed app.
	./Scripts/bundle.sh development

.PHONY: app-hardened
app-hardened: ## Same, but under the hardened runtime. Rehearses a shippable build.
	./Scripts/bundle.sh rehearsal

# Needs a Developer ID Application certificate. Pass it as IDENTITY=... or export
# UTTRFLOW_SIGNING_IDENTITY; bundle.sh says how to find it if neither is set.
.PHONY: app-dist
app-dist: ## Build a notarisable Uttrflow.app. Needs a Developer ID certificate.
	./Scripts/bundle.sh distribution $(if $(IDENTITY),"$(IDENTITY)")

.PHONY: notarise-check
notarise-check: ## Preflight dist/Uttrflow.app for notarisation. Needs no credentials.
	./Scripts/notarise.sh --check

.PHONY: notarise
notarise: ## Notarise and staple dist/Uttrflow.app. Needs Apple credentials.
	./Scripts/notarise.sh

# Needs nothing from Apple. hdiutil ships with macOS, so an ad-hoc app makes an
# unsigned image that is perfectly good for testing on another Mac; a Developer
# ID-signed app makes a signed one, using the certificate read back out of the app.
.PHONY: dmg
dmg: ## Wrap dist/Uttrflow.app in a disk image. Works without a Developer account.
	./Scripts/dmg.sh

.PHONY: notarise-dmg
notarise-dmg: ## Notarise and staple the disk image. Needs Apple credentials.
	./Scripts/notarise.sh $(wildcard dist/Uttrflow-*.dmg)

# The whole chain, in the one order that produces an app which still opens after it has
# been dragged out of the image and the image ejected: the app is notarised and stapled
# *first*, and the image is then built around a bundle that already carries its ticket.
# Doing it the other way round leaves the app depending on a ticket stapled to a disk
# image the user no longer has.
# Each stage is a separate $(MAKE) line, not a prerequisite list: prerequisites are
# siblings to GNU Make and `-j`, or an inherited MAKEFLAGS, could start notarise, dmg
# and notarise-dmg before app-dist finished. Recipe lines always run in order.
# The version is Resources/Uttrflow-Info.plist and nothing else — edited by hand when a
# release is cut, since a calendar version is the date that happens on. CFBundleShortVersionString
# is what people see (2026.9.14); CFBundleVersion is the build counter the updater compares,
# and has to increase every release.
.PHONY: release
release: ## Build, notarise and package a shippable disk image, strictly in that order.
	$(MAKE) app-dist
	$(MAKE) notarise
	$(MAKE) dmg
	$(MAKE) notarise-dmg
	@echo
	@echo "Ready to publish. Check it, then run: make publish"
	@ls -1 dist/Uttrflow-*.dmg

# Publishing is local rather than a workflow because every credential it needs is already
# on this Mac — the certificate in the keychain, the notary profile beside it, and gh
# logged in. A runner would need all four copied into secrets to do the same job, and
# would bill macOS minutes to do it.
.PHONY: publish
publish: ## Publish dist/*.dmg to the public downloads repository.
	./Scripts/publish.sh

.PHONY: publish-dry-run
publish-dry-run: ## Say exactly what `make publish` would do, and do none of it.
	./Scripts/publish.sh --dry-run

.PHONY: bakeoff
bakeoff: ## Score every clean-up engine. Downloads models; needs the Metal toolchain.
	@xcrun metal --version >/dev/null 2>&1 || \
		(echo "Metal toolchain missing. Run: xcodebuild -downloadComponent MetalToolchain" && exit 1)
	xcodebuild -scheme uttrflow-bakeoff -destination 'platform=macOS,arch=arm64' \
		-derivedDataPath .build/xcode -skipPackagePluginValidation -skipMacroValidation \
		-quiet build
	./.build/xcode/Build/Products/Debug/uttrflow-bakeoff $(ARGS)

.PHONY: clean
clean: ## Remove build products.
	rm -rf .build dist

.PHONY: help
help: ## List available targets.
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
