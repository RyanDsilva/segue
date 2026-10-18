# Security policy

## Reporting a vulnerability

Email **segue@ryandsilva.dev** with "Security" in the subject. Please do not open a GitHub issue, post on the feedback board or send it through the app's Report a Problem form: those are not private.

Include what you found, how to reproduce it, the Segue version (Segue > About Segue) and macOS version, and what an attacker could do with it. You will get a reply within 7 days. Segue is a one-person project, so there is no bug bounty, but you will be credited in the release notes if you would like.

## Supported versions

Only the latest release on the Mac App Store and the current `main` branch get security fixes.

## In scope

- **The Segue app**, both the App Store and the Personal flavour: reading and writing the song library (`.cho` files, `.segue.json` sidecars, the search index), import, export archives, Quick Look, the sandbox and entitlements, and running the user's Gig Mode Shortcuts.
- **What the app sends off the Mac**: consent handling for analytics and crash reports, the TelemetryDeck ingest client, Sentry crash, hang and bug-report envelopes (including anything sent without consent, or anything beyond the fields listed in the privacy policy), and log redaction.
- **The website** segue.ryandsilva.dev: the static pages, headers and redirects in `website/`.
- **This repository's build and release tooling**: scripts, Makefile targets and GitHub workflows, including any path that could leak a signing identity, App Store Connect API key or Sentry token.

## Out of scope

- The vendors' own platforms (Apple, TelemetryDeck, Sentry, Featurebase, Cloudflare, GitHub): report those to the vendor.
- Attacks that need an already compromised Mac or user account, or physical access to an unlocked one.
- Missing hardening headers or best-practice findings on the website without a concrete impact.
- Denial of service through deliberately huge or malformed files the user imports themselves.
- `research/`, which is experimental code that never ships.
