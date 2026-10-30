---
name: macos-app-architecture
description: Structuring a macOS app into a thin app target plus local Swift packages - where new code goes, layering a platform-neutral core under the UI, isolating third-party SDKs, and separate build flavors (e.g. personal vs App Store). Use whenever you add a feature, module, package, target, or third-party dependency to a Mac app, decide which module a file belongs in, edit Package.swift or Tuist/XcodeGen manifests, or untangle a dependency cycle, even if the user just says "add X".
---

# macOS app architecture

First learn the project's actual layout: list its targets and packages (Tuist/XcodeGen manifests, `Package.swift` files, the workspace), read any architecture or decisions docs, and see where similar features already live. Extend that structure; propose changes to it rather than working around it. If the project is generated (Tuist, XcodeGen), edit the manifest and regenerate, never the `.xcodeproj`.

## Thin app, features in packages

- The app target only composes: the `App` struct, scenes, the app delegate, and dependency wiring (creating services and injecting them into the environment). Almost no logic.
- Features live in local Swift packages so they build and test with `swift test`, fast, without launching the app. Logic left in the app target is reachable only by slow UI tests.
- App extensions (Quick Look, widgets, Share) link the same packages; follow the project's static/dynamic linking choice.

## Layers point one way

- **Core**: platform-neutral models, parsing, persistence, domain rules. No `SwiftUI` or `AppKit` imports, so it stays testable and portable (iOS later, CLI tools, extensions).
- **UI**: SwiftUI views, view models, theme, AppKit bridges. Depends on core, never the reverse.
- **App**: depends on everything and wires it together.
- A new module or folder may need registering in manifests, lint configs, or test maps; search for where existing ones are listed.
- Break a cycle by moving the shared type down a layer or putting a protocol in core, not by adding a reverse import.

## Isolate vendor SDKs

- Each third-party SDK (crash reporting, analytics, payments) is imported in exactly one module, behind a protocol the rest of the app owns. Core and UI talk to the protocol; the app wires in the real implementation, and tests get a fake or no-op.
- Enforce it mechanically: a lint rule (e.g. a SwiftLint `custom_rules` regex) that fails on `import VendorSDK` outside that module. Add to the existing rule when you add a vendor.
- Pin vendor versions exactly, and check a vendor SDK's current API in its source or docs, not from memory.

## Build flavors

- When the app ships in more than one form (personal vs store, free vs pro), give each flavor its own target/configuration and compile flag, and keep flavor-only code in its own package that the other flavor doesn't link.
- Gate on the flag at the composition point (app wiring), not deep inside views.
- Keep a check that the restricted build contains none of the excluded code (e.g. symbol or bundle inspection of the built product), and run it at the release gate.
