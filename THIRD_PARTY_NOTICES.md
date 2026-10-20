# Third-party notices

Segue itself is proprietary (see [LICENSE](LICENSE)). It ships the open-source components below, each under its own licence. The app shows no third-party notices in its UI. They accompany the binary instead: this file ships as `Segue.app/Contents/Resources/THIRD_PARTY_NOTICES.md`, and the full licence texts ship in the SegueUI resource bundle (`Licenses/` and the font's `Fonts/OFL.txt`). The website's [acknowledgements page](https://segue.ryandsilva.dev/acknowledgements) (from `credits` in `content/site.json`, linked from the privacy policy, the terms and every page's footer) carries the same notices; `make site-check` fails if a credit there is missing from this file.

## Shipped in the app (both flavours)

| Component | Version | Source | Licence | Licence text in this repo |
|---|---|---|---|---|
| GRDB.swift | 7.11.1 | https://github.com/groue/GRDB.swift | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/GRDB.txt` |
| Tonic | 2.1.2 | https://github.com/AudioKit/Tonic | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/Tonic.txt` |
| Sentry Cocoa SDK (sentry-cocoa) | 9.30.2 | https://github.com/getsentry/sentry-cocoa | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/Sentry.txt` |
| MLX Swift LM (mlx-swift-lm) | 3.32.3 | https://github.com/ml-explore/mlx-swift-lm | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/MLXSwiftLM.txt` |
| MLX Swift (mlx-swift) | 0.32.3 | https://github.com/ml-explore/mlx-swift | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/MLXSwift.txt` |
| swift-transformers | 1.3.5 | https://github.com/huggingface/swift-transformers | Apache-2.0 | `Packages/SegueUI/Sources/SegueUI/App/Licenses/SwiftTransformers.txt` |
| swift-huggingface | 1.0.0 | https://github.com/huggingface/swift-huggingface | Apache-2.0 | `Packages/SegueUI/Sources/SegueUI/App/Licenses/SwiftHuggingFace.txt` |
| swift-jinja | 2.5.2 | https://github.com/huggingface/swift-jinja | Apache-2.0 | `Packages/SegueUI/Sources/SegueUI/App/Licenses/SwiftJinja.txt` |
| Swift Crypto (swift-crypto) | 4.5.2 | https://github.com/apple/swift-crypto | Apache-2.0 | `Packages/SegueUI/Sources/SegueUI/App/Licenses/SwiftCrypto.txt`, `SwiftCrypto-NOTICE.txt` |
| SwiftASN1 (swift-asn1) | 1.7.3 | https://github.com/apple/swift-asn1 | Apache-2.0 | `Packages/SegueUI/Sources/SegueUI/App/Licenses/SwiftASN1.txt`, `SwiftASN1-NOTICE.txt` |
| Swift Collections (swift-collections) | 1.7.3 | https://github.com/apple/swift-collections | Apache-2.0 with Runtime Library Exception | `Packages/SegueUI/Sources/SegueUI/App/Licenses/SwiftCollections.txt` |
| Swift Numerics (swift-numerics) | 1.1.1 | https://github.com/apple/swift-numerics | Apache-2.0 with Runtime Library Exception | `Packages/SegueUI/Sources/SegueUI/App/Licenses/SwiftNumerics.txt` |
| yyjson | 0.12.0 | https://github.com/ibireme/yyjson | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/yyjson.txt` |
| EventSource | 1.5.1 | https://github.com/mattt/EventSource | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/EventSource.txt` |
| Schibsted Grotesk (Regular, Medium, SemiBold, Bold, ExtraBold) | 1.100 | https://github.com/schibsted/schibsted-grotesk | SIL Open Font License 1.1 | `Packages/SegueUI/Sources/SegueUI/Theme/Fonts/OFL.txt` |

Versions are the exact pins in `Tuist/Package.swift`, `Packages/SegueCore/Package.swift` and `Tuist/Package.resolved` (GRDB.swift at `b83108d`, Tonic at `601eeb2`, sentry-cocoa at `4bb2282`, mlx-swift-lm at `3b339ad`, mlx-swift at `1960120`, swift-transformers at `4847310`, swift-huggingface at `c30143a`, swift-jinja at `1e4d0dc`, swift-crypto at `da9d28d`, swift-asn1 at `3b6410f`, swift-collections at `35a1edc`, swift-numerics at `0c0290f`, yyjson at `8b4a38d`, EventSource at `86b5096`, swift-syntax at `79e4b74`); the font version is the `name` table of the bundled TTFs. `make docs-check` fails if a pin in `Tuist/Package.resolved` is missing from the tables in this file, so a dependency bump must update this file in the same change.

### GRDB.swift

Copyright (C) 2015-2025 Gwendal Roué. MIT License; full text in `GRDB.txt` (byte-identical to the `LICENSE` file of the 7.11.1 release).

### Tonic

Copyright (c) 2022 Audulus LLC. MIT License; full text in `Tonic.txt` (byte-identical to the `LICENSE` file of the 2.1.2 release).

### Sentry Cocoa SDK

Copyright (c) 2015 Sentry. MIT License; full text in `Sentry.txt` (byte-identical to the `LICENSE.md` of the 9.30.2 release, from the resolved package source at `4bb2282`). Linked into both app flavours through `Packages/SegueVendorServices`; it sends crash and hang reports only if the user allows crash reports.

### Schibsted Grotesk

Copyright 2023 The Schibsted-Grotesk Project Authors (https://github.com/schibsted/schibsted-grotesk). Licensed under the SIL Open Font License, Version 1.1; full text in `OFL.txt`. The font files are bundled unmodified and never sold on their own.

### MLX Swift LM

Copyright (c) 2024 ml-explore. MIT License; full text in `MLXSwiftLM.txt` (byte-identical to the `LICENSE` file of the 3.32.3 release). Provides the on-device language-model runtime (`MLXLLM`, `MLXLMCommon`) and the XGrammar-based constrained decoding.

### MLX Swift

Copyright (c) 2023 ml-explore. MIT License; full text in `MLXSwift.txt` (byte-identical to the `LICENSE` file of the 0.32.3 release).

### swift-transformers

Copyright 2022 Hugging Face SAS. Apache License 2.0; full text in `SwiftTransformers.txt` (byte-identical to the `LICENSE` file of the 1.3.5 release). Segue uses its `Tokenizers` product, which pulls in `Hub`.

### swift-huggingface

Copyright 2025 Hugging Face SAS. Apache License 2.0; full text in `SwiftHuggingFace.txt` (byte-identical to the `LICENSE` file of the 1.0.0 release). Linked through `Hub`.

### swift-jinja

Copyright 2022 Hugging Face SAS. Apache License 2.0; full text in `SwiftJinja.txt` (byte-identical to the `LICENSE` file of the 2.5.2 release). Renders the model's chat template.

### Swift Crypto

Copyright 2019 The SwiftCrypto Project (Apple Inc. and the SwiftCrypto project authors). Apache License 2.0; full text in `SwiftCrypto.txt` and its NOTICE file in `SwiftCrypto-NOTICE.txt` (byte-identical to `LICENSE.txt` and `NOTICE.txt` of the 4.5.2 release). Linked through `Hub`.

### SwiftASN1

Copyright 2022 The SwiftASN1 Project (Apple Inc. and the SwiftASN1 project authors). Apache License 2.0; full text in `SwiftASN1.txt` and its NOTICE file in `SwiftASN1-NOTICE.txt` (byte-identical to `LICENSE.txt` and `NOTICE.txt` of the 1.7.3 release). Linked through Swift Crypto.

### Swift Collections

Copyright (c) Apple Inc. and the Swift project authors. Apache License 2.0 with the Runtime Library Exception; full text in `SwiftCollections.txt` (byte-identical to the `LICENSE.txt` of the 1.7.3 release).

### Swift Numerics

Copyright (c) Apple Inc. and the Swift Numerics project authors. Apache License 2.0 with the Runtime Library Exception; full text in `SwiftNumerics.txt` (byte-identical to the `LICENSE.txt` of the 1.1.1 release).

### yyjson

Copyright (c) 2020 YaoYuan <ibireme@gmail.com>. MIT License; full text in `yyjson.txt` (byte-identical to the `LICENSE` file of the 0.12.0 release).

### EventSource

Copyright 2025 Mattt (https://mat.tt). MIT License; full text in `EventSource.txt` (byte-identical to the `LICENSE.md` of the 1.5.1 release). Linked through swift-huggingface.

## Resolved but not shipped

| Component | Version | Source | Licence | Licence text in this repo |
|---|---|---|---|---|
| swift-syntax | 603.0.2 | https://github.com/swiftlang/swift-syntax | Apache-2.0 with Runtime Library Exception | none (not distributed) |

swift-syntax is resolved only as the compiler-side macro host of mlx-swift-lm's `MLXHuggingFaceMacros`, which Segue does not use; no swift-syntax code is linked into either app flavour.

## Vendored inside those packages

These have no pin of their own: they are source copies inside the packages above and are compiled into the app with them.

| Component | Version | Where | Licence | Licence text in this repo |
|---|---|---|---|---|
| MLX (C++ core) | 0.32.2 | mlx-swift `Source/Cmlx/mlx` (https://github.com/ml-explore/mlx) | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/MLX.txt` |
| mlx-c | 0.6.0 | mlx-swift `Source/Cmlx/mlx-c` (https://github.com/ml-explore/mlx-c) | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/MLXC.txt` |
| metal-cpp | macOS 26 / iOS 26 headers | mlx-swift `Source/Cmlx/metal-cpp` (https://developer.apple.com/metal/cpp/) | Apache-2.0 | `Packages/SegueUI/Sources/SegueUI/App/Licenses/MetalCpp.txt` |
| {fmt} | 12.1.0 | mlx-swift `Source/Cmlx/fmt` (https://github.com/fmtlib/fmt) | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/fmt.txt` |
| JSON for Modern C++ (nlohmann/json) | 3.11.3 | mlx-swift `Source/Cmlx/json` (https://github.com/nlohmann/json) | MIT | `Packages/SegueUI/Sources/SegueUI/App/Licenses/NlohmannJSON.txt` |
| XGrammar | 0.1.30 | mlx-swift-lm `Libraries/MLXCXGrammar/xgrammar` (https://github.com/mlc-ai/xgrammar) | Apache-2.0 | `Packages/SegueUI/Sources/SegueUI/App/Licenses/XGrammar.txt`, `XGrammar-NOTICE.txt` |
| DLPack (header) | 1.0 | XGrammar `3rdparty/dlpack` (https://github.com/dmlc/dlpack) | Apache-2.0 | `Packages/SegueUI/Sources/SegueUI/App/Licenses/XGrammar.txt` (same unmodified Apache-2.0 text) |
| PicoJSON (header) | as vendored by XGrammar 0.1.30 | XGrammar `3rdparty/picojson` (https://github.com/kazuho/picojson) | BSD-2-Clause | `Packages/SegueUI/Sources/SegueUI/App/Licenses/PicoJSON.txt` |

Versions are read from the vendored sources themselves: `mlx/version.h`, the `MLX_C_VERSION` default in mlx-c's `CMakeLists.txt`, the metal-cpp `README.md` changelog, `FMT_VERSION` in `fmt/base.h`, `NLOHMANN_JSON_VERSION_*` in the json headers, XGrammar's `VERSION` file and `DLPACK_*_VERSION` in `dlpack.h`.

### MLX

Copyright © 2023 Apple Inc. MIT License; full text in `MLX.txt` (byte-identical to `Source/Cmlx/mlx/LICENSE` in mlx-swift 0.32.3).

### mlx-c

Copyright (c) 2023 ml-explore. MIT License; full text in `MLXC.txt` (byte-identical to `Source/Cmlx/mlx-c/LICENSE` in mlx-swift 0.32.3).

### metal-cpp

Copyright © 2024 Apple Inc. Apache License 2.0; full text in `MetalCpp.txt` (byte-identical to `Source/Cmlx/metal-cpp/LICENSE.txt` in mlx-swift 0.32.3).

### {fmt}

Copyright (c) 2012 - present, Victor Zverovich and {fmt} contributors. MIT License (with the {fmt} object-code exception); full text in `fmt.txt` (byte-identical to `Source/Cmlx/fmt/LICENSE` in mlx-swift 0.32.3).

### JSON for Modern C++

Copyright (c) 2013-2022 Niels Lohmann. MIT License; full text in `NlohmannJSON.txt` (byte-identical to `Source/Cmlx/json/LICENSE.MIT` in mlx-swift 0.32.3).

### XGrammar

Copyright (c) 2024 by XGrammar Contributors. Apache License 2.0; full text in `XGrammar.txt` and its NOTICE file in `XGrammar-NOTICE.txt` (byte-identical to `Libraries/MLXCXGrammar/xgrammar/LICENSE` and `NOTICE` in mlx-swift-lm 3.32.3).

### DLPack

Copyright (c) 2017 by Contributors (header notice in `dlpack.h`). Apache License 2.0. XGrammar vendors only the `dlpack.h` header, without a licence file of its own; its terms are the unmodified Apache-2.0 text in `XGrammar.txt`.

### PicoJSON

Copyright 2009-2010 Cybozu Labs, Inc. and Copyright 2011-2014 Kazuho Oku. BSD 2-Clause License; full text in `PicoJSON.txt` (the licence comment at the top of `3rdparty/picojson/picojson.h` in mlx-swift-lm 3.32.3, copied verbatim, since the header ships without a separate licence file).

## Downloaded on request (never bundled)

| Component | Source | Licence | Licence text in this repo |
|---|---|---|---|
| Qwen3-4B-Instruct-2507 model weights (4-bit MLX conversion) | https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit, converted from https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507 | Apache-2.0 | `Packages/SegueUI/Sources/SegueUI/App/Licenses/XGrammar.txt` (same unmodified Apache-2.0 text) |

The weights are not part of the app or the website. The app downloads them from huggingface.co only when the user asks for the on-device model, and stores them on the user's Mac. It is the locked curated model (docs/release/decisions.md R119); a future swap must update this section.

## Served by the website

The website (`website/`) serves WOFF2 subsets of Schibsted Grotesk 400, 600, 700 and 800, generated from the bundled TTFs by `scripts/gen-webfonts.sh` (recorded in `content/fonts.lock.json`). Subsetting makes them Modified Versions under the OFL; they keep the original family name, which the OFL allows because the font declares no Reserved Font Name. `website/assets/fonts/OFL.txt` carries the licence next to them.

## Development only (never distributed)

These run on Ryan's machine or in CI and are not part of the app or the website: Tuist, SwiftLint, SwiftFormat, actionlint, ShellCheck, jq, uv, Node.js and pnpm (pinned in `.mise.toml`), fonttools (via `uvx`), html-validate and Wrangler (via `pnpm dlx`, versions in the `Makefile`). The phase 3 research spike in `research/phase3-spikes/` resolves its own packages (see its `Package.resolved`); it is excluded from every shipped target. MLX Swift, swift-transformers and their dependencies are no longer development only: the app ships them (see above).
