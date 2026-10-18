# Contributing

Segue is a solo, proprietary project (see [LICENSE](LICENSE)); outside contributions are not accepted. This file records the working conventions for Ryan and for agent sessions.

## Source of truth

- [docs/release/decisions.md](docs/release/decisions.md) and [docs/decisions.md](docs/decisions.md) are canonical. Specs follow them; code follows the specs. When code and a spec disagree, stop and ask rather than picking one.
- Issues point back at the spec or decision they implement; they never replace it.
- Behaviour changes update the relevant doc in the same commit.

## Branches and pushes

- Work lands on `main`. A short-lived branch (`ws2b-welcome`, `fix-autoscroll`) is fine for anything that wants CI before it reaches `main`; see [docs/github-setup.md](docs/github-setup.md) for how branch protection treats direct pushes.
- Pushes need Ryan's explicit go-ahead. The pre-push hook (`make bootstrap` installs it) stands in for branch protection: it blocks a push unless every pushed commit is signed and `make repo-check` passes, and, because a push to `main` publishes the website, runs `make site-check STRICT=1` whenever `website/` or `content/` changed. See [docs/github-setup.md](docs/github-setup.md).

## Commits

- **Signed**, always: `git commit -S` (SSH signing through the 1Password agent). If signing fails with "failed to fill whole buffer", 1Password is locked: unlock it and retry, never commit unsigned.
- **Conventional prefixes**, as in `git log`: `feat`, `fix`, `test`, `docs`, `build`, `ci`, `chore`, `style`, plus `website` for the site. Optional scope: `feat(live): ...`, `fix(editor): ...`. Reference the spec step or ruling when there is one: `(WS1 step 7)`, `(R45)`.
- One logical change per commit, revertible on its own. No co-author trailers.
- Never edit a generated file by hand (`make tokens`, `make icon`, `make site`), and never edit CHANGELOG-style generated output; the website changelog comes from `content/changelog.json`.
- No em dashes anywhere in the repo; use "-". `make docs-check` enforces it.

## Checks and the test budget

Tests are integration-first: real parser, real file-system library, real index, real app UI on freshly reset state. Add unit tests only for tricky pure logic.

| When | Run |
|---|---|
| Each step | Filtered suites only: `make quick` (lint, Personal build, package tests without the long ones) and `make e2e-one TEST=Class[/testName]` for the UI you touched |
| Each assignment (workstream gate) | `make quick`, then `make gate`: package tests, the App Store build (or verify-appstore when the App Store's contents may have changed), the E2E smoke set and the E2E classes `UITests/e2e-map.tsv` maps your changed paths to (since `GATE_BASE`, default `origin/main`) |
| Before pushing | `make repo-check` (exactly what CI runs: lint, token and HTML checks, docs-check, ShellCheck, actionlint) |
| Release (before `make archive`/`validate`) and the end of each phase | `make check` (everything, once: the release gate) |

`make e2e-smoke` runs just the smoke set (library to editor to setlist to live). Do not run the full `make check` after every small fix; it is the release gate, not the inner loop. A new source folder needs a line in `UITests/e2e-map.tsv` (an unmapped path makes `make gate` run the full suite). Logic belongs in in-process SegueUI tests (real stores, files and parser); XCUITest is for real user flows. See [docs/test-performance.md](docs/test-performance.md). Flaky tests, lint warnings and build warnings get fixed when seen, even when unrelated to the change at hand.

## Tools

All tools come from [`.mise.toml`](.mise.toml) via `mise exec`; never install them globally. To add or bump one, change its pin there and in any workflow that installs it (the workflows install only the tools they use).

## Dependencies

GRDB and Tonic are pinned `exact:` in both `Tuist/Package.swift` and `Packages/SegueCore/Package.swift`; bump both together (Dependabot groups them into one PR). A bump also updates [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), the licence copy in `Packages/SegueUI/Sources/SegueUI/App/Licenses/` if it changed, and passes a full `make check`.

## Issues

GitHub Issues are Ryan's dev tracker, labelled from [.github/labels.yml](.github/labels.yml). Users report problems through Help > Report a Problem (Sentry) and request features on [the board](https://segue.featurebase.app/); anything worth keeping is copied into an issue by hand.
