# Segue - thin wrappers over tuist / xcodebuild / swift. Tools come from .mise.toml.
# Run `make bootstrap` once after cloning (and `make generate` after manifest changes).

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := check

MISE        := mise exec --
CORE_DIR    := Packages/SegueCore

# xcodebuild on the generated workspace; fails on any warning Xcode records.
XCODEBUILD  := scripts/xcodebuild.sh

.PHONY: bootstrap generate build build-appstore test e2e lint format verify-appstore check

bootstrap: ## Install pinned tools, fetch dependencies, generate the workspace
	mise install
	$(MISE) tuist install
	$(MISE) tuist generate --no-open

generate: ## Regenerate the workspace after editing manifests
	$(MISE) tuist generate --no-open

build: ## Build the Personal flavor
	$(XCODEBUILD) -scheme Segue-Personal -configuration Debug-Personal build

build-appstore: ## Build the App Store flavor
	$(XCODEBUILD) -scheme Segue-AppStore -configuration Debug-AppStore build

test: ## Core integration suite + parser corpus (Swift Testing)
	cd $(CORE_DIR) && swift test

e2e: ## XCUITest suite against the Personal flavor
	$(XCODEBUILD) -scheme Segue-Personal -configuration Debug-Personal test

lint: ## Lint + format check (no changes)
	$(MISE) swiftlint lint --strict --quiet
	$(MISE) swiftformat --lint .

format: ## Auto-format and auto-fix lint where possible
	$(MISE) swiftformat .
	$(MISE) swiftlint lint --fix --quiet

verify-appstore: ## Build the App Store flavor and assert no personal-module symbols
	scripts/verify-appstore.sh

check: lint build build-appstore test e2e verify-appstore ## Everything CI would run
