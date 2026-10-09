# Uttrflow — developer entry points.
#
# Every target here is what CI runs, so "green locally" and "green in CI" cannot
# diverge. Xcode supplies the toolchain; the build itself is Swift Package Manager.

export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

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

.PHONY: developer-dir-test
developer-dir-test: ## Prove Make preserves a configured Xcode developer directory. Needs Xcode.
	./Scripts/developer_dir_test.sh

.PHONY: comment-audit
comment-audit: ## Prove no file gained a multi-line comment. Needs no build.
	@python3 Scripts/comment_audit.py

.PHONY: comment-report
comment-report: ## List the multi-line comments left, worst file first.
	@python3 Scripts/comment_audit.py --report

.PHONY: seam-audit
seam-audit: ## Prove no corpus cut gained a difference between cleaning its pieces and cleaning the whole.
	$(SWIFT) run uttrflow-dev seams --check Scripts/seam_baseline.json

.PHONY: corpus-edit-audit
corpus-edit-audit: ## Refuse a changed or removed evaluation case that Scripts/corpus_edits.txt does not name. Needs no build.
	@python3 Scripts/corpus_edit_audit_test.py
	@python3 Scripts/corpus_edit_audit.py

.PHONY: match-audit
match-audit: ## Prove no source file gained a word match decided by shape. Needs no build.
	@python3 Scripts/loose_match_audit.py

.PHONY: closed-list-audit
closed-list-audit: ## Prove no source file gained a literal list of four or more words. Needs no build.
	@python3 Scripts/closed_list_audit.py

.PHONY: closed-list-report
closed-list-report: ## List the closed word lists still written into code, with the line.
	@python3 Scripts/closed_list_audit.py --report

.PHONY: duplicate-table-audit
duplicate-table-audit: ## Prove no file gained a word table that copies one in another file. Needs no build.
	@python3 Scripts/duplicate_table_audit.py

.PHONY: duplicate-table-report
duplicate-table-report: ## List every pair of word tables in different files that hold the same members.
	@python3 Scripts/duplicate_table_audit.py --report

.PHONY: word-split-audit
word-split-audit: ## Prove no file gained text split into words by a hand-written separator. Needs no build.
	@python3 Scripts/word_split_audit.py

.PHONY: python-imports-audit
python-imports-audit: ## Refuse a Scripts/ Python import that is not standard library, a repository module, or pinned with a hash. Needs no build.
	@python3 Scripts/python_imports_audit.py
	@python3 Scripts/python_imports_audit_test.py

.PHONY: match-report
match-report: ## List the word matches still decided by shape, with the line.
	@python3 Scripts/loose_match_audit.py --report

.PHONY: accessibility-controls
accessibility-controls: ## Prove Docs/accessibility-controls.md lists every control in the view code, each with an accessible name. Needs no build.
	@python3 Scripts/accessibility_controls.py --check
	@python3 Scripts/accessibility_controls_test.py

.PHONY: layering-audit
layering-audit: ## Prove no logic module gained a UI-framework import or a platform dependency, and no module gained an edge outside Scripts/module_layers.json. Needs no build.
	@python3 Scripts/layering_audit.py

.PHONY: type-name-audit
type-name-audit: ## Prove no top-level type name gained a declaration in a second module. Needs no build.
	@python3 Scripts/type_name_audit.py

.PHONY: public-api-audit
public-api-audit: ## Prove no module gained a public declaration the baseline does not record. Needs no build.
	@python3 Scripts/public_api_audit.py

.PHONY: string-audit
string-audit: ## Prove no file gained a fixed English string handed to a view. Needs no build.
	@python3 Scripts/string_audit.py

.PHONY: ratchet-test
ratchet-test: ## Prove the comment, word-match, closed-list, duplicate-table, layering, public API, string and type-name baselines refuse a rise without --after-merge. Needs no build.
	@python3 Scripts/audit_ratchet_test.py
	@python3 Scripts/loose_match_audit_test.py
	@python3 Scripts/closed_list_audit_test.py
	@python3 Scripts/duplicate_table_audit_test.py
	@python3 Scripts/word_split_audit_test.py
	@python3 Scripts/layering_audit_test.py
	@python3 Scripts/public_api_audit_test.py
	@python3 Scripts/string_audit_test.py
	@python3 Scripts/type_name_audit_test.py

.PHONY: mutation-probe-test
mutation-probe-test: ## Prove the mutation probe finds each mutation it names and refuses the main checkout. Needs no build.
	@python3 Scripts/mutation_probe_test.py

.PHONY: range-test
range-test: ## Prove the disclosure audit reads every revision range the pre-push hook hands it. Needs no build.
	@python3 Scripts/disclosure_range_test.py

.PHONY: hits-test
hits-test: ## Prove the disclosure audit counts every same-line match, not just the first per pattern. Needs no build.
	@python3 Scripts/disclosure_hits_test.py

.PHONY: live-tally-test
live-tally-test: ## Prove a skipped live-model suite is counted as skipped, not run. Needs no build.
	@python3 Scripts/live_model_tally_test.py

.PHONY: pre-push-test
pre-push-test: ## Prove the pre-push hook uses the disclosure audit paired with the hook, not the worktree's copy. Needs no build.
	@python3 Scripts/pre_push_hook_test.py

.PHONY: pre-push-lock-test
pre-push-lock-test: ## Prove the verify-worktree lock recovers from a missing or dead owner without the 30-minute wait. Needs no build.
	@python3 Scripts/pre_push_lock_recovery_test.py

.PHONY: update-feed-test
update-feed-test: ## Prove the release scripts parse update-feed URLs by host, not prefix.
	@python3 Scripts/update_feed_gate_test.py

.PHONY: entitlement-gate-test
entitlement-gate-test: ## Prove the release gates read entitlement Boolean values, not just key names.
	@python3 Scripts/entitlement_gate_test.py

.PHONY: test-name-audit
test-name-audit: ## Refuse a test file named after an issue number. Needs no build.
	@python3 Scripts/test_name_audit.py

.PHONY: issue-template-audit
issue-template-audit: ## Refuse a public issue template that prompts for content the disclosure rule forbids. Needs no build.
	@python3 Scripts/issue_template_audit.py

.PHONY: audio-audit
audio-audit: ## Refuse audio outside the synthetic fixture directory: a recording is personal data. Needs no build.
	@python3 Scripts/audio_audit.py --self-test

.PHONY: root-audit
root-audit: ## Refuse any file or directory at the repository root that is not on the allowlist. Needs no build.
	@python3 Scripts/root_layout_audit.py --self-test

.PHONY: context-reach-audit
context-reach-audit: ## Refuse a context module that reads by clipboard, posted keys, screen capture or text recognition. Needs no build.
	@python3 Scripts/context_reach_audit.py --self-test

.PHONY: issue-template-test
issue-template-test: ## Prove the issue template audit catches the bug it was written for. Needs no build.
	@python3 Scripts/issue_template_audit_test.py

.PHONY: dependabot-labels-test
dependabot-labels-test: ## Keep Dependabot's automatically created default labels enabled.
	@python3 Scripts/dependabot_labels_test.py

.PHONY: flake-audit
flake-audit: ## Refuse a quarantined flaky test past its expiry, and prove the flake report. Needs no build.
	@python3 Scripts/flake_report_test.py
	@python3 Scripts/flake_report.py --check-quarantine

.PHONY: store-permissions
store-permissions: ## Prove nothing writes a local store's files except through PrivateFile. Needs no build.
	@python3 Scripts/store_permissions_audit.py

.PHONY: uitest-arguments
uitest-arguments: ## Prove the UI harness refuses a rounds count it cannot run. Compiles it; needs no screen.
	@python3 Scripts/uitest_arguments_test.py

.PHONY: eval-arguments
eval-arguments: build ## Prove transcribe refuses negative report limits before measuring.
	@python3 Scripts/eval_arguments_test.py

ACCURACY_CORPUS := .build/accuracy-corpus
ACCURACY_BASELINE := Scripts/accuracy_baseline.json

.PHONY: accuracy-gate
accuracy-gate: ## Fail when the shipping recogniser got worse on the synthesised passages. Needs the installed model.
	$(SWIFT) build -c release --product uttrflow-eval $(SWIFT_BUILD_FLAGS)
	rm -rf $(ACCURACY_CORPUS) .build/accuracy-results
	./.build/release/uttrflow-eval synthesise --corpus-path $(ACCURACY_CORPUS)
	./.build/release/uttrflow-eval transcribe --corpus-path $(ACCURACY_CORPUS) \
		--results-path .build/accuracy-results --baseline $(ACCURACY_BASELINE) --fail-on-regression

.PHONY: accuracy-report
accuracy-report: ## Write a release's accuracy report from the committed baseline: make accuracy-report VERSION=26.0926.0
	@test -n "$(VERSION)" || { echo "usage: make accuracy-report VERSION=<release version>" >&2; exit 2; }
	$(SWIFT) build -c release --product uttrflow-eval $(SWIFT_BUILD_FLAGS)
	./.build/release/uttrflow-eval accuracy-report --version $(VERSION) --baseline $(ACCURACY_BASELINE)

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

# Every design check, each self-test first; Docs/agents/design.md says what each enforces. Runs them all, then fails if any failed.
DESIGN_AUDITS := design_source_audit design_token_parity_audit design_contrast_audit identity_role_audit \
	design_sidebar_contract_audit design_chrome_contract_audit design_dictation_contract_audit \
	design_diagnostics_contract_audit insights_contract_audit signin_artboard_contract_audit design_audit

.PHONY: design-audit
design-audit: ## Prove colours, typefaces, design generators, canvases and contrast follow Docs/agents/design.md. Needs no build.
	@failed=""; \
	for audit in $(DESIGN_AUDITS); do \
		printf '\n== %s\n' "$$audit"; \
		python3 "Scripts/$$audit.py" --self-test >/dev/null && python3 "Scripts/$$audit.py" || failed="$$failed $$audit"; \
	done; \
	if ! sed -n 's/^verify:\([^#]*\).*/\1/p' Makefile | grep -qw design-audit; then failed="$$failed verify-chain"; fi; \
	if [ -n "$$failed" ]; then printf '\ndesign-audit: FAILED:%s (see Docs/agents/design.md)\n' "$$failed" >&2; exit 1; fi; \
	printf '\ndesign-audit: every design check passed\n'

.PHONY: docs-audit
docs-audit: ## Prove the documentation still describes this tree, including that CLAUDE.md delegates to AGENTS.md. Needs no build.
	@python3 Scripts/preview_gen_test.py
	@python3 Scripts/rule_file_duplicate_audit.py --self-test
	@python3 Scripts/rule_file_duplicate_audit.py
	./Scripts/docs_audit.sh --self-test

.PHONY: data-manifest
data-manifest: ## Prove every bundled resource file is in Resources/DataManifest.json with its digest. Needs no build.
	@python3 Scripts/data_manifest_test.py
	@python3 Scripts/data_manifest.py
	@cd Scripts && python3 ngram_sources_test.py
	@cd Scripts && python3 derive_lexicon_test.py
	@python3 Scripts/ngram_sources.py

.PHONY: assets
assets: ## Rebuild the derived data assets from the pinned sources, then check them against their manifest digest and budget. ASSET_CACHE=folder outside the repository.
	@test -n "$(ASSET_CACHE)" || { echo "assets: set ASSET_CACHE to a folder outside the repository; see Docs/data-manifest.md" >&2; exit 1; }
	@python3 Scripts/ngram_sources.py --fetch --cache "$(ASSET_CACHE)"
	@python3 Scripts/derive_lexicon.py --cache "$(ASSET_CACHE)"
	@python3 Scripts/data_manifest.py

.PHONY: claims-audit
claims-audit: ## Refuse a privacy, accuracy or speed claim in user-facing text that Docs/claims.json does not back. Needs no build.
	@python3 Scripts/claims_audit.py --self-test

.PHONY: pii-audit
pii-audit: ## Prove no personal data is in the tree. Needs no build.
	./Scripts/pii_audit.sh

.PHONY: log-audit
log-audit: ## Prove no log message carries text a person typed, read or said. Needs no build.
	@python3 Scripts/log_privacy_audit.py --self-test

.PHONY: perf-budget
perf-budget: ## Prove the source keeps to the energy and memory budget, and that each check still bites. No build.
	@python3 Scripts/perf_budget_audit.py --self-test

# Needs a `uttrflow-dev bench` run, so it runs on a Mac rather than in CI.
.PHONY: perf-budget-latency
perf-budget-latency: ## Fail when a bench run's p95 for any stage is over its budget. RUN=path to the run.
	@python3 Scripts/perf_budget_audit.py --latency "$(RUN)"

.PHONY: size-budget
size-budget: ## Prove the size budget check bites, and that the resolved Swift packages fit their count. No build.
	@python3 Scripts/size_budget.py --self-test

.PHONY: idle-wakeups
idle-wakeups: ## Fail when the built app, idle in the menu bar, wakes or computes over the budget. Needs `make app` first.
	@python3 Scripts/idle_wakeups.py --self-test

# Needs the speech model and the suggestion model on disk, so it runs on a Mac rather than in CI.
.PHONY: perf-budget-models
perf-budget-models: ## Fail when the model harness reads memory, or the support folder reads disk, over the budget. Needs both models installed.
	$(MAKE) bakeoff ARGS="gpu-memory --passes 12 --release"
	$(MAKE) bakeoff ARGS="profile --dictations 10"

.PHONY: pasteboard-audit
pasteboard-audit: ## Prove only the clipboard adapters touch NSPasteboard. Needs no build.
	./Scripts/pasteboard_audit.sh

.PHONY: release-tag-test
release-tag-test: ## Prove release tags come from main. Needs no build.
	./Scripts/release_tag_ancestry_test.sh

.PHONY: release-notes-test
release-notes-test: ## Prove release notes render and the leading-dash printf regression fails. Needs no build.
	./Scripts/release_notes_test.sh

.PHONY: provider-mark-test
provider-mark-test: ## Prove the Google mark selector recognises both the legacy and current archive layouts. Needs no build.
	./Scripts/select_google_mark_test.sh

.PHONY: release-order-test
release-order-test: ## Prove `make release` keeps its stages in order under -j. Dry-run only.
	./Scripts/release_order_test.sh

.PHONY: notarise-dmg-test
notarise-dmg-test: ## Prove notarise-dmg refuses zero or multiple images and selects the only image without credentials.
	./Scripts/notarise_dmg_test.sh

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

.PHONY: dependency-pin-test
dependency-pin-test: ## Prove selected in-process dependencies match Package.resolved and release flags. Needs no build.
	python3 Scripts/dependency_pin_audit.py --self-test
	python3 Scripts/dependency_pin_audit.py

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
verify: pii-audit data-manifest audio-audit root-audit disclosure-audit issue-template-audit test-name-audit docs-audit design-audit comment-audit corpus-edit-audit match-audit closed-list-audit duplicate-table-audit word-split-audit accessibility-controls layering-audit public-api-audit string-audit type-name-audit python-imports-audit ratchet-test mutation-probe-test range-test hits-test hook-test pre-push-test pre-push-lock-test update-feed-test entitlement-gate-test issue-template-test dependabot-labels-test dependency-pin-test flake-audit uitest-arguments eval-arguments uitest-result-path developer-dir-test log-audit store-permissions pasteboard-audit context-reach-audit bundle-requirement-test bundle-test release-tag-test release-notes-test provider-mark-test release-order-test notarise-dmg-test soak-test e2e-predict-cleanup-test publish-resume-test publish-cleanup-test offline-audit-tokenizer-test offline-test exclusion-audit perf-budget size-budget lint build seam-audit coverage offline-audit ## The whole gate: audits, package and release checks, soak and notarisation checks, lint, build, tests, coverage, and offline audit.

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
	./Scripts/fetch-provider-marks.sh || echo "Continuing without the Google mark; the sign-in button shows its wording alone."
	./Scripts/bundle.sh

.PHONY: app-preflight
app-preflight: data-manifest app ## Build the app bundle and run CI's strict signature verification.
	codesign --verify --deep --strict dist/Uttrflow.app

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
	./Scripts/fetch-provider-marks.sh
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
	./Scripts/notarise_dmg.sh

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
		| awk 'BEGIN {FS = ":.*?## "}; {names[NR] = $$1; descriptions[NR] = $$2; if (length($$1) > width) width = length($$1)} END {for (i = 1; i <= NR; i++) printf "  \033[36m%-*s\033[0m %s\n", width, names[i], descriptions[i]}'
