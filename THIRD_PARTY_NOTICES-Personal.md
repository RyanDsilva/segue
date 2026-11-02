# Third-party notices (Personal build)

Components linked only by the Personal flavour, which is never distributed (R139). This file ships as `Segue.app/Contents/Resources/THIRD_PARTY_NOTICES-Personal.md` in the Personal app only, beside `THIRD_PARTY_NOTICES.md`; the App Store build contains none of these components and never ships this file (checked by `make verify-appstore`). `make docs-check` reads this table together with `THIRD_PARTY_NOTICES.md`.

| Component | Version | Source | Licence | Licence text in this repo |
|---|---|---|---|---|
| SwiftSoup | 2.14.3 | https://github.com/scinfu/SwiftSoup | MIT | `Packages/SeguePersonalModules/Licenses/SwiftSoup.txt` |

The version is the exact pin in `Packages/SeguePersonalModules/Package.swift`, `Tuist/Package.swift` and `Tuist/Package.resolved` (SwiftSoup at `e7f85f4`).

### SwiftSoup

Copyright (c) 2009-2025 Jonathan Hedley, (c) 2016-2025 Nabil Chatbi (Swift port). MIT License; full text in `SwiftSoup.txt` (byte-identical to the `LICENSE` file of the 2.14.3 release), shipped beside this file. The HTML parser of the Personal build's web page import.
