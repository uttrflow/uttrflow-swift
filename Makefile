# Uttrflow — developer entry points.
#
# Every target here is what CI runs, so "green locally" and "green in CI" cannot
# diverge. Xcode supplies the toolchain; the build itself is Swift Package Manager.

export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

SWIFT := xcrun swift
SOURCES := Sources Tests

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

.PHONY: comment-audit
comment-audit: ## Prove no file gained a multi-line comment. Needs no build.
	@python3 Scripts/comment_audit.py

.PHONY: comment-report
comment-report: ## List the multi-line comments left, worst file first.
	@python3 Scripts/comment_audit.py --report

.PHONY: pii-audit
pii-audit: ## Prove no personal data is in the tree. Needs no build.
	./Scripts/pii_audit.sh

# `pii-audit` first, and `offline-audit` last, for opposite reasons.
#
# The PII audit reads source and nothing else, so it costs two seconds. Putting it ahead
# of the build is what makes it useful: somebody who has pasted a real address into a
# fixture is told before a five-minute build, not after one, and a check people wait
# through is a check they learn to skip. It is also the only step here whose failure
# cannot be fixed after the fact — this repository is going public, and a published
# address stays published.
#
# `offline-audit` last, because it reads the built object files and so needs `build` to
# have run. It is in the gate rather than beside it because it had drifted for weeks
# without anybody noticing: a check nothing runs is a check that is already wrong, and
# this one polices the claim the whole product is sold on.
.PHONY: verify
verify: pii-audit comment-audit lint build coverage offline-audit ## The whole gate: PII, comments, lint, build, tests, coverage floor, offline audit.

# Hooks are not cloned — .git/hooks is local to a checkout — so this points git at a
# directory that is. One command per clone, and the gate cannot be forgotten after that.
.PHONY: hooks
hooks: ## Install the pre-push gate that replaced CI.
	@git config core.hooksPath .githooks
	@echo "pre-push gate installed. 'make verify' runs before any push to main."
	@echo "Skip it deliberately with: git push --no-verify"

.PHONY: app
app: ## Build and sign Uttrflow.app into dist/ for this Mac.
	./Scripts/bundle.sh

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
# The version is Resources/Uttrflow-Info.plist and nothing else — edited by hand when a
# release is cut, which for semantic versioning is the only moment the number can be
# decided anyway. CFBundleShortVersionString is what people see (0.1.0);
# CFBundleVersion is the build counter beside it, and only has to increase.
.PHONY: release
release: app-dist notarise dmg notarise-dmg ## Build, notarise and package a shippable disk image.
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
