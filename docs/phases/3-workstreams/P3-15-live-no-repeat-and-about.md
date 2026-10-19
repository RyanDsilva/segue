# P3-15 - No repeats within a show, and the About panel (variant A)

Wave 3 (new, 2026-10-19; after P3-12's live-side break rows). Two small, independent items; one commit each. Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 2, 7 "NL picks", 12, 14, and 16.1 question 29). Rulings: `docs/release/decisions.md` R102 (no repeats in live mode), the walkthrough rule (a song appears at most once per setlist, enforced since commit 1d027df), R103 (About panel variant A), R15 (About panel), R30 (copyright), R79 (accessibility walk); WS2a spec section 3.6 (About).

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Part 1 - No repeats within a show (R102)

**Rule:** during a show, adding a song that was **already played** or is **still upcoming** in that show is refused with a clear message. For an upcoming song the message offers **"Move to Next"** instead (moves the existing entry; never a second entry). Applies to every add path: Insert Next, Play Now, a request (quick search "add request"), and any queue path.

Existing code: `SegueCore/Shows/ShowController.swift` (`ShowAction.addRequest`, `.insertNext`, `.playNow` ~271; `queuedRequests`), `ShowRecord.swift` + `ShowRecord+Transitions.swift` (played/skipped/pending items; break items from P3-12), `ReorderDiff.swift` (show-end save already drops repeats), `SegueUI/Live/QuickSearchModel.swift` + `QuickSearchOverlay.swift` (result rows), `LivePresentations.swift`, `LiveSession+Commands.swift`.

Steps:

**Question 29 (skipped songs and rehearsals) blocks the classification details** until Ryan rules; recommendation a: refuse only songs actually played, in gigs and rehearsals alike; a skipped song may be added back.

1. **Core:** one check in `ShowController` before each add transition: classify the song as `alreadyPlayed` (per question 29), `upcoming` (a pending set item or a queued request), or `free`. `free` adds as today; `alreadyPlayed` returns a typed refusal; `upcoming` returns a refusal carrying a "move to next" option that, when confirmed, reorders the existing item. The record stays at-most-once at all times.
2. **UI:** quick-search result rows show the state before the user acts ("Played" / "Up next in set" badges, VoiceOver labels that say it); acting on such a row shows the message ("Already played tonight" / "Already in the set: Move to Next?") in the stage's existing presentation style, keyboard-confirmable, never blocking the show, never a modal that hides the lyrics. P3-7 owns the lexicon hook in `QuickSearchModel`; you own the state badges and the refusal presentation.
3. **Tests:** Core scenario tests (`ShowScenarioTests` style): Insert Next of a played song refused; of an upcoming song -> Move to Next reorders, count unchanged; a request for a queued request refused; break rows (P3-12) never count as songs. In-process stage test for the badges and message. E2E: extend `SegueLiveE2ETests` (or a new `SegueLiveRepeatE2ETests`): start the Welcome Set, play song 1, quick search for it -> "Already played tonight".

## Part 2 - About panel, variant A (R103)

Existing code: `SegueUI/App/AboutPanel.swift` (native `orderFrontStandardAboutPanel` with credits: site host, Help, Support, Privacy Policy over two lines, link colour `cueText`). The three rendered variants (A native, B pro app, C brand card) are in the orchestrator's scratchpad (`about-variants/`); Ryan picked **A**.

Steps:

1. Keep the native system panel: icon, name, "Version 0.5 (N)", the copyright (R30) and **ONE row of links: Website, Help, Support, Privacy Policy** (labels exactly these; "Website" links to `SegueLinks.site`), centred, set on one line with no-break spaces inside each label and a separator between them; no other credits text.
2. **Dark-mode legibility (known issue):** the system panel dims its credits text view in dark mode. Verify the link row's contrast in both appearances (screenshots of the real panel in light and dark, contrast of the rendered link colour against the panel background at or above 4.5:1); if the system dimming lowers it, set the colour on the panel's text view after it appears (as `styleLinks` does today) or choose a token that stays legible. Attach both screenshots to the hand-off.
3. Tests: the existing About tests updated (credits string = the four labels in order with the right URLs); `make site-check` style URL check already covers the targets (`89a813e`).

## Files owned

`ShowController.swift` add paths (P3-12 owns break-item handling; coordinate if both are in flight), `ShowRecord+Transitions.swift` (the move-to-next transition), quick-search state badges and the refusal presentation in `Live/`, `App/AboutPanel.swift` and its tests, the E2E additions above.

## Acceptance

No path can add a song twice within a show; the user always sees why and, for an upcoming song, can move it to next in one step; the About panel shows exactly one row of four legible links in light and dark; `make quick` + `make gate` green.
