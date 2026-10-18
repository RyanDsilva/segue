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

.PHONY: bootstrap generate tokens tokens-check icon icon-check build build-appstore test e2e lint format \
	verify-appstore check site-fonts

bootstrap: ## Install pinned tools, fetch dependencies, generate the workspace
	mise install
	$(MISE) tuist install
	$(MISE) tuist generate --no-open

generate: ## Regenerate the workspace after editing manifests
	$(MISE) tuist generate --no-open

tokens: ## Regenerate colour tokens (asset catalog, Swift, website tokens.css) from design/tokens.json
	scripts/gen-tokens.swift

tokens-check: ## Fail if the generated colour tokens are stale
	scripts/gen-tokens.swift --check

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

verify-appstore: ## Build the App Store flavor and assert no personal-module symbols
	scripts/verify-appstore.sh

check: lint tokens-check icon-check build build-appstore test e2e verify-appstore ## Everything CI would run
