---
name: apple-api-check
description: Verify an Apple API (SwiftUI, AppKit, Foundation, Observation, Synchronization, any SDK framework) against what the project already uses and what the installed Xcode SDK actually declares, before writing or recommending it. Use whenever you are about to introduce an Apple API you have not seen in this codebase, are unsure whether something is deprecated, renamed or available at the deployment target, are fixing a deprecation warning, or another skill says to check an API. Use it even when you feel confident, because training data lags the SDK.
---

# Apple API check

Your memory of Apple APIs is a snapshot. The project's code and the installed SDK are the live truth, so check in this order and stop as soon as you have an answer.

## 1. How does this project already do it?

Grep the repo for the API or the job it does (`rg 'onChange\(of:'`, `rg 'NavigationSplitView'`). If the codebase has an established pattern, follow it: it compiles today with this project's settings. Also find the deployment target and language mode (`MACOSX_DEPLOYMENT_TARGET`, `platforms:` in `Package.swift`, Tuist/XcodeGen manifests, `SWIFT_VERSION`, strict-concurrency flags) because every answer below depends on them.

## 2. What does the installed SDK declare?

```bash
.claude/skills/apple-api-check/scripts/sdk-api.sh -m SwiftUI 'func onChange'      # declarations + availability
.claude/skills/apple-api-check/scripts/sdk-api.sh -m AppKit 'class NSHostingView'
.claude/skills/apple-api-check/scripts/sdk-api.sh -l                               # modules in this SDK
```

Each match prints its `@available` lines. Read them against the deployment target:
- `deprecated: <version>` at or below the target: the build will warn; use the replacement in `message:`/`renamed:`.
- `deprecated: 100000.0` is a soft deprecation: no warning yet, but new code should use the replacement.
- `macOS <version>` above the target: needs `if #available` or a different API.

## 3. Does it compile here?

For anything non-trivial, prove it with the compiler at the project's target:

```bash
.claude/skills/apple-api-check/scripts/typecheck.sh -t 26.0 - <<'EOF'
import SwiftUI
struct Probe: View { var body: some View { Text("x").foregroundStyle(.red) } }
EOF
```

Warnings and errors are the build's own verdict. The snippet can import SDK frameworks only, not project modules.

## 4. Documentation (behaviour, not signatures)

When you need semantics the declaration can't tell you, fetch current docs:
- `https://sosumi.ai/documentation/<framework>/<symbol>` returns Markdown of Apple's page.
- `https://developer.apple.com/tutorials/data/documentation/<framework>/<symbol>.json` is the raw DocC JSON.

If the `xcode` MCP server (`xcrun mcpbridge`) is connected and Xcode has the project open, `RunCodeSnippet` and `XcodeRefreshCodeIssuesInFile` can check code inside the real target, project modules included. Newer Xcodes may add a documentation tool; list its tools and prefer one if present.

## Report

When an API choice matters, say which source settled it ("SDK 27.0 marks X deprecated in macOS 14; using Y, as `Foo.swift` already does"). Never present a remembered signature as verified.
