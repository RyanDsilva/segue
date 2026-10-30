---
name: macos-testing
description: How to test a macOS app well and cheaply - choosing between in-process tests and XCUITest, Swift Testing vs XCTest, writing UI tests that don't flake, and launching the app into a known clean state. Use whenever you write, fix, or run tests for a Mac app, add a feature that needs coverage, debug a slow or flaky UI test, or decide which tests to run after a change, even if the user only says "add a test" or "make sure it works".
---

# macOS testing

First read how this project tests: its test targets, the commands that run them (Makefile, scripts, CI, CONTRIBUTING), and an existing test close to yours. Follow its harness and naming.

## Spend test time in tiers

- **After each small change:** run only the fast, targeted in-process tests for the code you touched (`swift test --filter`, `-only-testing:`).
- **At a milestone or before committing a batch:** run the project's full gate, including UI tests.
- **New UI tests only for core user flows** (launch, the main create/edit path). Everything else gets fast in-process coverage.

If the project defines quick and gate targets, use them; they encode this budget.

## Put logic where it tests fast

- Use **Swift Testing** (`@Test`, `#expect`, `#require`, arguments) for logic, model, and view-model tests, with real components (a real parser, a store on a temp directory) over mocks.
- Use **XCTest** only for XCUITest, which still needs it.
- If a UI test checks a computation, sort order, or formatting, move that check into an in-process model test and keep the UI test to the visible flow.
- Swift Testing changes each Xcode release. Copy the project's style and check any unfamiliar trait or macro with the `apple-api-check` skill.

## UI tests that don't flake

- Wait by **polling a condition** (about every 50 ms, with a deadline) through one shared helper (`waitUntil`, `appears`, `disappears`). No fixed `sleep`, no scattered `waitForExistence`: one helper is one place to fix timing.
- **Bring the app to the front before every input.** Another app, a notification, or a Space switch can steal focus and send keystrokes elsewhere; activate the app and confirm it is frontmost with a window first.

## Launch into a known state

Every UI test and manual check starts from a clean, known baseline:
- The app reads **test-only launch arguments** (e.g. `-UITesting YES`, `-ResetState YES`, `-FixtureDataPath <dir>`), parsed in one place and inert in release builds.
- Pass `-ApplePersistenceIgnoreState YES` so macOS window restoration doesn't reopen last run's windows.
- Point data at a fresh temporary fixture location, never real user data (a sandboxed app needs its container or a debug-only entitlement exception).
- Suppress one-time UI (onboarding, tips, review prompts) with a flag.

If the project lacks these, propose adding them before building UI tests on shared state.
