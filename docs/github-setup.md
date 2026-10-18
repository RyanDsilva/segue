# GitHub setup

Repo settings that cannot live in files, as the exact `gh` commands. Everything file-based (workflows, Dependabot, issue forms, labels, CODEOWNERS) is in `.github/`. Rulings: `docs/release/decisions.md` R47-R50. Changing a setting needs Ryan's go-ahead; this page records what was applied and when.

Repo: `RyanDsilva/segue` (private, GitHub Free). Run from the repo root with `gh` authenticated as RyanDsilva.

## 1. Applied 2026-10-17 (approved by Ryan)

### Description, homepage and topics

```sh
gh repo edit RyanDsilva/segue \
  --description "Segue - chord charts, setlists and a stage view for live gigs. Native macOS app for the Mac App Store." \
  --homepage https://segue.ryandsilva.dev \
  --add-topic macos,swift,swiftui,chordpro,setlist,chord-charts,live-music,musicians,mac-app-store,tuist
```

### Dependabot alerts and security updates

Version updates come from `.github/dependabot.yml`. Alerts and security updates are repo settings:

```sh
gh api -X PUT repos/RyanDsilva/segue/vulnerability-alerts          # Dependabot alerts (dependency graph on)
gh api -X PUT repos/RyanDsilva/segue/automated-security-fixes      # Dependabot security update PRs
gh api repos/RyanDsilva/segue/automated-security-fixes             # check: {"enabled":true,...}
```

### Labels

```sh
DRY_RUN=1 make labels-sync   # preview the gh commands
make labels-sync             # create or update every label in .github/labels.yml
```

Pruned 2026-10-17 with Ryan's go-ahead: `PRUNE=1 make labels-sync` deleted every label not in `labels.yml`, which were GitHub's defaults `accessibility`, `bug`, `documentation`, `duplicate`, `enhancement`, `good first issue`, `help wanted`, `invalid`, `question` and `wontfix` (no issue or PR used them). The repo now has exactly the 26 labels in `labels.yml`.

### Milestones

```sh
gh api repos/RyanDsilva/segue/milestones -f title=v0.5 \
  -f description="First Mac App Store release (docs/release/README.md)"
gh api repos/RyanDsilva/segue/milestones -f title=v0.6 \
  -f description="First update after the App Store launch"
```

## 2. Branch protection on `main` (not applied)

**Blocker: branch protection and rulesets on a private repository need GitHub Pro (or a public repo).** On GitHub Free the API answers `403 Upgrade to GitHub Pro or make this repository public to enable this feature.` (checked 2026-10-17). The command below is ready for the day the repo is on GitHub Pro or public; it must also wait until the workflows have been pushed and have run once, because required checks name CI jobs GitHub has seen.

### Until then: the pre-push hook enforces it

`.githooks/pre-push` (installed by `make bootstrap` through `core.hooksPath`) blocks any push unless:

1. every commit being pushed has a good signature (`git log --format=%G?` is `G`, or `U` for a good signature from a key of unknown validity). Unlock 1Password before pushing;
2. `make repo-check` passes (the same checks CI runs);
3. if a pushed commit touches `website/` or `content/`, `make site-check STRICT=1` passes (no placeholders or draft maker note on the live site).

The first push may need a one-time bypass of check 3 only, while the site is still "Coming soon": `SEGUE_ALLOW_SITE_PLACEHOLDERS=1 git push origin main`. Checks 1 and 2 still run. Never export it in a shell profile.

A hook is local: `git push --no-verify` skips it, and a fresh clone has no hook until `make bootstrap`. That is acceptable for a solo repo; server-side enforcement comes back with the command below.

Required checks are the CI job names: `Swift lint`, `Scripts and workflows` (lint.yml), `Site tokens`, `Site HTML` (site.yml) and `Docs` (docs.yml). `app_id` 15368 is GitHub Actions.

```sh
gh api -X PUT repos/RyanDsilva/segue/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": {
    "strict": false,
    "checks": [
      { "context": "Swift lint", "app_id": 15368 },
      { "context": "Scripts and workflows", "app_id": 15368 },
      { "context": "Site tokens", "app_id": 15368 },
      { "context": "Site HTML", "app_id": 15368 },
      { "context": "Docs", "app_id": 15368 }
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
gh api -X POST repos/RyanDsilva/segue/branches/main/protection/required_signatures
gh api repos/RyanDsilva/segue/branches/main/protection --jq '{checks: .required_status_checks.checks, admins: .enforce_admins.enabled, signed: .required_signatures.enabled}'
```

No pull request is required (solo project). `strict` is off, so a commit does not have to be rebased on the latest `main` before its checks count.

### Include administrators or not

Required status checks are checked **before** a commit can land on `main`, and a direct push carries commits whose checks have not run yet. So:

- **`"enforce_admins": false` (recommended).** Ryan, as admin, keeps pushing straight to `main`; GitHub lets the push through and records it as a bypass. Checks then run on `main` after the fact. Dependabot PRs and anyone else still need green checks and signed commits. Cost: protection is advisory for Ryan, so `make repo-check` before pushing stays the real gate.
- **`"enforce_admins": true`.** Nothing reaches `main` unchecked, Ryan included. Every change goes to a branch first, waits for CI, then lands with a fast-forward: `git push origin HEAD:refs/heads/staging`, wait for green, `git push origin HEAD:main`. Cost: two pushes and a CI wait for every change, and a red CI run on a branch blocks a hotfix unless protection is relaxed.

Signed commits are enforced either way for non-admins; with `enforce_admins: true` they are enforced for Ryan too (his SSH-signed commits already show as Verified on GitHub).
