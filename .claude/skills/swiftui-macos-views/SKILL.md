---
name: swiftui-macos-views
description: Writing and reviewing SwiftUI for macOS apps - data flow with Observation, scenes and windows, Settings, menus and keyboard shortcuts, toolbars, focus, AppKit bridging, accessibility, and avoiding deprecated APIs. Use whenever you create or change a SwiftUI view, window, menu command or settings pane in a Mac app, wrap an AppKit view, review SwiftUI code, or fix SwiftUI deprecation warnings, even for a small view tweak.
---

# SwiftUI on macOS

Start from the project, not from memory: find the nearest existing view that does something similar and match its structure, naming, styling tokens, and identifier conventions. Note the deployment target; it decides which APIs you may use. Check any API you haven't seen in this codebase with the `apple-api-check` skill.

## Avoid stale APIs

LLM-written SwiftUI reaches for older APIs out of habit. Before using anything from `references/deprecation-suspects.md`, confirm its status with `apple-api-check` against this SDK and target. The list names patterns to verify, not verdicts: the SDK decides. When you touch a file that has warnings, fix them; the build should stay at zero.

## Data flow

- Model state with `@Observable` classes (Observation). Don't add `ObservableObject`/`@Published` in new code when the target supports Observation; follow the project if it is mid-migration.
- `@State private var` for state a view owns, including an `@Observable` model it creates. Pass models down as plain properties; use `@Bindable` only where you need bindings into one.
- Use the environment for app-wide services, injected at the scene or root view. Avoid singletons reached from views.
- Keep views thin: logic lives in the model or view model, where fast in-process tests can reach it.
- UI types are main-actor; respect the project's default-isolation setting rather than scattering `@MainActor` or `nonisolated` to silence errors.

## macOS app surfaces

- Pick the scene to fit: `WindowGroup` for multiple windows, `Window` for a single one, `Settings` for preferences (opened with `openSettings`/`SettingsLink`), `MenuBarExtra` for menu-bar items.
- Menus belong in `Commands`. Give every frequent action a menu item with a keyboard shortcut, and place items in the standard menus (`CommandGroup(after:/replacing:)`) where macOS users expect them.
- Use `.toolbar` with explicit placements, `.focusedValue`/`@FocusedValue` to route menu commands to the active window, and `.focusable`/`@FocusState` for keyboard flow.
- Bridge to AppKit only for real gaps: `NSViewRepresentable` with a `Coordinator` for delegates, updating the AppKit view from `updateNSView` without recreating it; `NSHostingView`/`NSHostingController` to put SwiftUI into AppKit. Keep the bridge small and in its own file.

## Accessibility and appearance

- Give every interactive or test-relevant element an `.accessibilityIdentifier` from the project's central list, and a meaningful label for VoiceOver when the control has no visible text.
- Everything must work from the keyboard: tab order, default and cancel buttons, shortcuts, no hover-only controls.
- Use semantic colours and styles (or the project's tokens) so light, dark, and increased-contrast all work, and respect the user's System / Light / Dark appearance setting. No hard-coded colours or fixed font sizes in a view.
