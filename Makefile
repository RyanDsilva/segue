# Segue - thin wrappers over tuist / xcodebuild / swift. Tools come from .mise.toml.
# Run `make bootstrap` once after cloning (and `make generate` after manifest changes).

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := check

MISE        := mise exec --
CORE_DIR    := Packages/SegueCore
UI_DIR      := Packages/SegueUI

# xcodebuild on the generated workspace; fails on any warning Xcode records.
XCODEBUILD  := scripts/xcodebuild.sh

# Package tests (Swift Testing). No index store: nothing reads it from the command line
# (Xcode the IDE keeps its own), and writing it costs compile time.
SWIFT_TEST  := swift test --disable-index-store
# SegueUI's theme tests need Swift Build (the native build system copies asset catalogs
# uncompiled). Swift Build suppresses warnings in the non-root SegueCore package, which
# conflicts with its warnings-as-errors setting, so warnings are failed by grep instead.
UI_TEST     := $(SWIFT_TEST) --build-system swiftbuild -Xswiftc -no-warnings-as-errors
# Timing-budget tests (the *PerformanceTests suites and the 2,000-song quick search): they
# run alone in `test-perf`, never beside another build or test run.
PERF_TESTS  := PerformanceTests|over 2000 tagged songs
# Long property tests `make quick` skips (`make test`, gate and check run them).
SLOW_TESTS  := random command sequences
# Swift Testing regexes: what test-packages leaves out and what test-perf runs (quick
# leaves out the long property tests and the 2,000-song search, which take 10-14 s each).
PKG_SKIP    := $(PERF_TESTS)
PERF_RUN    := $(PERF_TESTS)

# The E2E smoke set (docs/test-performance.md C3): the primary path, library to editor to
# setlist to live. `make e2e-smoke` runs it; `make gate` runs it plus the mapped classes.
E2E_SMOKE   := LaunchSmokeTests SegueE2ETests/testSongToSetlistToLiveView \
	SegueEditorE2ETests/testEditorFlow SegueLiveE2ETests/testFridayGig \
	SegueSetlistBuilderE2ETests/testBuildSetlistFromTheLibrary \
	SegueCoreUXE2ETests/testAutosaveWritesWithoutSave

# Website tooling (dev-only, fetched at run time at exact versions; nothing ships).
HTMLVALIDATE := pnpm dlx html-validate@11.16.4
WRANGLER     := pnpm dlx wrangler@4.151.1

.PHONY: bootstrap generate tokens tokens-check icon icon-check build build-appstore test test-packages \
	test-perf e2e e2e-one e2e-smoke gate quick eval-ai lint format verify-appstore check bump \
	site-fonts site-html guide guide-dev guide-check guide-keys docs-shots docs-clips docs-check shellcheck actionlint repo-check \
	release-notes labels-sync clean-local archive validate upload upload-dsyms probe-shortcuts

bootstrap: ## Install pinned tools and Xcode's Metal Toolchain, fetch dependencies, generate the workspace
	mise install
	git config core.hooksPath .githooks
	# MLX's Metal kernels need Xcode's downloadable Metal Toolchain (P3-A section 5.1).
	xcodebuild -showComponent MetalToolchain 2>/dev/null | grep 'Status: installed' >/dev/null \
		|| xcodebuild -downloadComponent MetalToolchain
	$(MISE) tuist install
	$(MISE) tuist generate --no-open

generate: ## Regenerate the workspace after editing manifests
	$(MISE) tuist generate --no-open

tokens: ## Regenerate colour tokens (asset catalog, Swift, website tokens.css) from design/tokens.json
	scripts/gen-tokens.swift

tokens-check: ## Fail if the generated colour tokens are stale
	scripts/gen-tokens.swift --check

site: ## Regenerate the website: tokens.css, changelog, slots, redirects, sitemap
	scripts/gen-tokens.swift
	scripts/gen-site.swift

site-check: tokens-check site-html guide guide-check ## Fail if the website or guide is stale or invalid (STRICT=1 also refuses placeholders)
	scripts/gen-site.swift --check $(if $(STRICT),--strict)

site-html: ## Validate every hand-written website page with html-validate (runs on Linux too; not the built guide)
	$(MISE) $(HTMLVALIDATE) --config .htmlvalidate.json $$(find website -name '*.html' -not -path 'website/guide/*' -not -path 'website/guide.html' | sort)

site-serve: guide ## Preview the site and the built guide with Cloudflare's Pages emulator (redirects, headers, 404)
	WRANGLER_SEND_METRICS=false $(MISE) $(WRANGLER) pages dev website --port 8788

# User guide (WS6): Astro Starlight in guide/, built into website/guide (gitignored); Cloudflare
# Pages builds it from source with scripts/pages-build.sh.
guide: ## Build the user guide into website/guide (frozen install, links validated)
	cd guide && $(MISE) pnpm install --frozen-lockfile --silent
	cd guide && ASTRO_TELEMETRY_DISABLED=1 $(MISE) pnpm --silent build

guide-dev: ## Live-reloading guide preview at http://localhost:4321/guide
	cd guide && $(MISE) pnpm install --frozen-lockfile --silent
	cd guide && ASTRO_TELEMETRY_DISABLED=1 $(MISE) pnpm dev

guide-check: ## Static checks on the guide source and build (runs on Linux; STRICT=1 refuses placeholder shots)
	$(MISE) node guide/scripts/check.mjs $(if $(STRICT),--strict)

guide-keys: ## Regenerate guide/src/data/keyboard.json from the app's menu and stage key tables
	cd $(UI_DIR) && SEGUE_WRITE_GUIDE_DATA=1 $(UI_TEST) --filter GuideKeyboardExportTests

docs-shots: ## Guide screenshots from the App Store flavour, dark and light (needs the screen; ONLY=id,id)
	scripts/docs-shots.sh shots $(ONLY)

docs-clips: ## Guide how-to clips from the App Store flavour (needs the screen and Screen Recording; ONLY=id)
	scripts/docs-shots.sh clips $(ONLY)

site-raster: ## Re-render OG image, touch icon, favicon PNG, wordmark PNGs and screenshot JPEGs
	scripts/gen-site.swift --raster

site-fonts: ## Rebuild the subset WOFF2 web fonts from the bundled TTFs
	scripts/gen-webfonts.sh

icon: ## Regenerate the app icon layers, .icon bundle and previews, and the .cho document icon
	scripts/gen-icon.swift
	scripts/gen-doc-icon.swift

icon-check: ## Fail if the generated icon layers or Segue.icon are stale
	scripts/gen-icon.swift --check

build: ## Build the Personal flavor
	$(XCODEBUILD) -scheme Segue-Personal -configuration Debug-Personal build

build-appstore: ## Build the App Store flavor
	$(XCODEBUILD) -scheme Segue-AppStore -configuration Debug-AppStore build

test: test-packages test-perf ## All package tests: the four packages side by side, then the timing budgets alone

test-packages: ## Package tests of SegueCore, SegueVendorServices, SegueAI and SegueUI side by side (no timing budgets)
	mkdir -p .build
	scripts/parallel.sh \
		core "cd $(CORE_DIR) && $(SWIFT_TEST) --skip '$(PKG_SKIP)'" \
		vendor "cd Packages/SegueVendorServices && $(SWIFT_TEST) --skip '$(PKG_SKIP)'" \
		ai "cd Packages/SegueAI && $(SWIFT_TEST) --skip '$(PKG_SKIP)'" \
		ui "cd $(UI_DIR) && $(UI_TEST) --skip '$(PKG_SKIP)' 2>&1 | tee ../../.build/ui-test.log"
	! grep -E 'Packages/[^:]+\.swift:[0-9]+:[0-9]+: warning:' .build/ui-test.log

test-perf: ## The timing-budget package tests, one package at a time with nothing else running
	cd $(CORE_DIR) && $(SWIFT_TEST) --filter '$(PERF_RUN)'
	cd $(UI_DIR) && $(UI_TEST) --filter '$(PERF_RUN)'

e2e: ## XCUITest suite against the Personal flavor (all classes)
	$(XCODEBUILD) -scheme Segue-Personal -configuration Debug-Personal test

e2e-one: ## Run selected UI tests only: make e2e-one TEST=SegueLiveE2ETests[/testName]
	@test -n "$(TEST)" || (echo "usage: make e2e-one TEST=Class[/test]" >&2; exit 2)
	$(XCODEBUILD) -scheme Segue-Personal -configuration Debug-Personal test -only-testing:SegueUITests/$(TEST)

e2e-smoke: ## The E2E smoke set: library to editor to setlist to live (E2E_SMOKE)
	$(XCODEBUILD) -scheme Segue-Personal -configuration Debug-Personal test \
		$(addprefix -only-testing:SegueUITests/,$(E2E_SMOKE))

quick: PKG_SKIP := $(PERF_TESTS)|$(SLOW_TESTS)
quick: PERF_RUN := PerformanceTests
quick: lint build test-packages test-perf ## Inner loop: lint, build, package tests (no UI tests, no long property tests)

gate: generate lint repo-check tokens-check icon-check site-check build ## Workstream gate: package tests, App Store build or verify, E2E smoke + classes mapped from changes since GATE_BASE (default origin/main)
	E2E_SMOKE="$(E2E_SMOKE)" scripts/gate.sh

lint: ## Lint + format check (no changes)
	$(MISE) swiftlint lint --strict --quiet
	$(MISE) swiftformat --lint .
	plutil -lint Config/ExportOptions-AppStore.plist App/PrivacyInfo.xcprivacy App/*.entitlements

format: ## Auto-format and auto-fix lint where possible
	$(MISE) swiftformat .
	$(MISE) swiftlint lint --fix --quiet

bump: ## Bump + commit the build number; `make bump VERSION=0.6` sets the marketing version
	scripts/bump-version.sh $(if $(VERSION),marketing $(VERSION),build)

# Release (docs/release/specs/WS1-release-pipeline.md 4.7). Not part of `check`. validate,
# upload and upload-dsyms read credentials with 1Password's `op`, so Ryan runs them in
# Terminal.app (R46); DRY_RUN=1 does everything except the credentialed steps.
archive: ## Archive + export the App Store .pkg and run verify-archive (no upload)
	scripts/release.sh archive

validate: ## archive (or reuse it), then App Store Connect validation (API key from 1Password; DRY_RUN=1)
	scripts/release.sh validate $(if $(DRY_RUN),--dry-run)

upload: ## validate, upload the verified .pkg, signed local tag, dSYMs to Sentry (never pushes; DRY_RUN=1)
	scripts/release.sh upload $(if $(DRY_RUN),--dry-run)

upload-dsyms: ## Upload an archive's dSYMs to Sentry (ARCHIVE=path or DSYMS=dir; DRY_RUN=1)
	@test -n "$(ARCHIVE)$(DSYMS)" || (echo "usage: make upload-dsyms ARCHIVE=<xcarchive> | DSYMS=<dir>" >&2; exit 2)
	scripts/upload-dsyms.sh $(if $(DRY_RUN),--dry-run) $(ARCHIVE)

probe-shortcuts: ## R35 probe: build the sandboxed Shortcuts Events probe app (research/shortcuts-events-probe)
	research/shortcuts-events-probe/build.sh

eval-ai: ## Manual: real FM + MLX over the paste fixtures and local pastes vs the baseline (BASELINE=1, RECORD=1, PROVIDERS=, MODEL=); never in check or gate
	scripts/eval-ai.sh

verify-appstore: ## Build the App Store flavor and assert no personal-module symbols
	scripts/verify-appstore.sh

check: generate lint repo-check tokens-check icon-check site-check build ## Release gate, everything: CI checks, builds, all package tests, verify-appstore, the full E2E suite
	# verify-appstore (which builds Debug- and Release-AppStore) runs beside the package
	# tests; the timing budgets run after both, and E2E (keystroke latency) last, alone.
	scripts/parallel.sh tests "make --no-print-directory test-packages" \
		verify "make --no-print-directory verify-appstore"
	$(MAKE) --no-print-directory test-perf
	$(MAKE) --no-print-directory e2e

# Repo hygiene. repo-check is exactly what the Linux CI runs (.github/workflows), offline apart
# from the first fetch of pinned tools, so run it before pushing. gen-site.swift needs AppKit,
# so the full site-check stays local (the pre-push hook enforces it for website changes).
docs-check: ## No em dashes, valid JSON and YAML metadata, third-party notices match the pins
	$(MISE) scripts/check-docs.sh

shellcheck: ## Lint shell scripts and git hooks (scripts/lib is checked through its callers)
	$(MISE) shellcheck scripts/*.sh .githooks/pre-push

actionlint: ## Lint the GitHub workflows (shellchecks their run: steps too)
	$(MISE) actionlint

repo-check: lint tokens-check site-html docs-check shellcheck actionlint ## The Linux CI checks, locally

release-notes: ## Preview the GitHub Release notes for a tag: make release-notes TAG=v0.5.0
	@test -n "$(TAG)" || (echo "usage: make release-notes TAG=vX.Y.Z" >&2; exit 2)
	$(MISE) scripts/release-notes.sh --title $(TAG)
	@echo
	$(MISE) scripts/release-notes.sh $(TAG)

labels-sync: ## Sync GitHub labels to .github/labels.yml (changes GitHub; DRY_RUN=1 to preview)
	$(MISE) scripts/sync-labels.sh

clean-local: ## Move throwaway local build clutter to the Trash (keeps the live DerivedData and caches)
	scripts/clean-local.sh
