## What and why

<!-- One or two sentences. Link the issue (Closes #...) and the spec or decision it implements. -->

## How it was tested

<!-- Integration or E2E first. Name the targets you ran. -->

- [ ] `make quick`
- [ ] `make e2e-one TEST=...` for touched UI
- [ ] `make repo-check` (the Linux CI checks, offline)
- [ ] Full `make check` (phase gates and release commits only)

## Checklist

- [ ] Commits are signed and use the conventional prefixes (CONTRIBUTING.md)
- [ ] Docs, specs or `docs/release/decisions.md` updated in the same change where behaviour changed
- [ ] Nothing personal-only reaches the App Store flavour (`make verify-appstore` when touching targets or modules)
- [ ] No generated file edited by hand (`make tokens`, `make site`, `make icon` instead)
- [ ] THIRD_PARTY_NOTICES.md and the acknowledgements updated if a dependency or font changed
