# Third-party notices

Segue itself is proprietary (see [LICENSE](LICENSE)). It ships the open-source components below, each under its own licence. The same notices appear in the app (the Acknowledgements window, from `Packages/SegueUI/Sources/SegueUI/App/Licenses/` and the font's `OFL.txt`) and on the website's [acknowledgements page](https://segue.ryandsilva.dev/acknowledgements) (from `credits` in `content/site.json`).

## Shipped in the app (both flavours)

| Component | Version | Source | Licence | Licence text in this repo |
|---|---|---|---|---|
| GRDB.swift | 7.11.1 | https://github.com/groue/GRDB.swift | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/GRDB.txt` |
| Tonic | 2.1.2 | https://github.com/AudioKit/Tonic | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/Tonic.txt` |
| Sentry Cocoa SDK (sentry-cocoa) | 9.30.2 | https://github.com/getsentry/sentry-cocoa | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/Sentry.txt` |
| Schibsted Grotesk (Regular, Medium, SemiBold, Bold, ExtraBold) | 1.100 | https://github.com/schibsted/schibsted-grotesk | SIL Open Font License 1.1 | `Packages/SegueUI/Sources/SegueUI/Theme/Fonts/OFL.txt` |

Versions are the exact pins in `Tuist/Package.swift`, `Packages/SegueCore/Package.swift` and `Tuist/Package.resolved` (GRDB.swift at `b83108d`, Tonic at `601eeb2`, sentry-cocoa at `4bb2282`); the font version is the `name` table of the bundled TTFs. `make docs-check` fails if a pin in `Tuist/Package.resolved` is missing from the table above, so a dependency bump must update this file in the same change.

### GRDB.swift

Copyright (C) 2015-2025 Gwendal Roué. MIT License; full text in `GRDB.txt` (byte-identical to the `LICENSE` file of the 7.11.1 release).

### Tonic

Copyright (c) 2022 Audulus LLC. MIT License; full text in `Tonic.txt` (byte-identical to the `LICENSE` file of the 2.1.2 release).

### Sentry Cocoa SDK

Copyright (c) 2015 Sentry. MIT License; full text in `Sentry.txt` (byte-identical to the `LICENSE.md` of the 9.30.2 release, from the resolved package source at `4bb2282`). Linked into both app flavours through `Packages/SegueVendorServices`; it sends crash and hang reports only if the user allows crash reports.

### Schibsted Grotesk

Copyright 2023 The Schibsted-Grotesk Project Authors (https://github.com/schibsted/schibsted-grotesk). Licensed under the SIL Open Font License, Version 1.1; full text in `OFL.txt`. The font files are bundled unmodified and never sold on their own.

## Served by the website

The website (`website/`) serves WOFF2 subsets of Schibsted Grotesk 400, 600, 700 and 800, generated from the bundled TTFs by `scripts/gen-webfonts.sh` (recorded in `content/fonts.lock.json`). Subsetting makes them Modified Versions under the OFL; they keep the original family name, which the OFL allows because the font declares no Reserved Font Name. `website/assets/fonts/OFL.txt` carries the licence next to them.

## Development only (never distributed)

These run on Ryan's machine or in CI and are not part of the app or the website: Tuist, SwiftLint, SwiftFormat, actionlint, ShellCheck, jq, uv, Node.js and pnpm (pinned in `.mise.toml`), fonttools (via `uvx`), html-validate and Wrangler (via `pnpm dlx`, versions in the `Makefile`). The phase 3 research spike in `research/phase3-spikes/` resolves its own packages (MLX Swift, swift-transformers and others, see its `Package.resolved`); it is excluded from every shipped target.
