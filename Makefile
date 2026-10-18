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

# Website tooling (dev-only, fetched at run time at exact versions; nothing ships).
HTMLVALIDATE := pnpm dlx html-validate@11.16.4
WRANGLER     := pnpm dlx wrangler@4.151.1

.PHONY: bootstrap generate tokens tokens-check icon icon-check build build-appstore test e2e lint format \
	verify-appstore check bump site-fonts site-html docs-check shellcheck actionlint repo-check \
	release-notes labels-sync clean-local

bootstrap: ## Install pinned tools, fetch dependencies, generate the workspace
	mise install
	git config core.hooksPath .githooks
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

site-check: tokens-check site-html ## Fail if the website is stale or invalid (STRICT=1 also refuses placeholders)
	scripts/gen-site.swift --check $(if $(STRICT),--strict)

site-html: ## Validate every website page with html-validate (runs on Linux too)
	$(MISE) $(HTMLVALIDATE) --config .htmlvalidate.json 'website/**/*.html'

site-serve: ## Preview the site locally with Cloudflare's Pages emulator (redirects, headers, 404)
	WRANGLER_SEND_METRICS=false $(MISE) $(WRANGLER) pages dev website --port 8788

site-raster: ## Re-render OG image, touch icon, favicon PNG, wordmark PNGs and screenshot JPEGs
	scripts/gen-site.swift --raster

site-fonts: ## Rebuild the subset WOFF2 web fonts from the bundled TTFs
	scripts/gen-webfonts.sh

icon: ## Regenerate the app icon layers, .icon bundle and previews from design/icon geometry
	scripts/gen-icon.swift

icon-check: ## Fail if the generated icon layers or Segue.icon are stale
	scripts/gen-icon.swift --check

build: ## Build the Personal flavor
	$(XCODEBUILD) -scheme Segue-Personal -configuration Debug-Personal build

build-appstore: ## Build the App Store flavor
	$(XCODEBUILD) -scheme Segue-AppStore -configuration Debug-AppStore build

test: ## Core integration suite + parser corpus + theme tokens (Swift Testing)
	cd $(CORE_DIR) && swift test
	# SegueUI theme tests need Swift Build (the native build system copies asset catalogs
	# uncompiled). Swift Build suppresses warnings in the non-root SegueCore package, which
	# conflicts with its warnings-as-errors setting, so warnings are failed by grep instead.
	mkdir -p .build
	cd $(UI_DIR) && swift test --build-system swiftbuild -Xswiftc -no-warnings-as-errors \
		2>&1 | tee ../../.build/ui-test.log
	! grep -E 'Packages/[^:]+\.swift:[0-9]+:[0-9]+: warning:' .build/ui-test.log

e2e: ## XCUITest suite against the Personal flavor
	$(XCODEBUILD) -scheme Segue-Personal -configuration Debug-Personal test

e2e-one: ## Run selected UI tests only: make e2e-one TEST=SegueLiveE2ETests[/testName]
	@test -n "$(TEST)" || (echo "usage: make e2e-one TEST=Class[/test]" >&2; exit 2)
	$(XCODEBUILD) -scheme Segue-Personal -configuration Debug-Personal test -only-testing:SegueUITests/$(TEST)

quick: lint build test ## Fast inner loop: lint, build, unit/integration tests (no UI tests)

lint: ## Lint + format check (no changes)
	$(MISE) swiftlint lint --strict --quiet
	$(MISE) swiftformat --lint .

format: ## Auto-format and auto-fix lint where possible
	$(MISE) swiftformat .
	$(MISE) swiftlint lint --fix --quiet

bump: ## Bump + commit the build number; `make bump VERSION=0.6` sets the marketing version
	scripts/bump-version.sh $(if $(VERSION),marketing $(VERSION),build)

verify-appstore: ## Build the App Store flavor and assert no personal-module symbols
	scripts/verify-appstore.sh

check: generate lint repo-check tokens-check icon-check site-check build build-appstore test e2e verify-appstore ## Everything: the CI checks plus builds and tests

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
