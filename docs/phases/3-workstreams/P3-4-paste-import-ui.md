# P3-4 - Paste and import UI, menus, Welcome card/tip and AI analytics events

Wave 3 (after P3-1 and P3-2). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 3, 6, 11, 16.0). Rulings: `docs/release/decisions.md` R61-R79 (R63, R69, R71, R74, R75, R76), R15 (Trash), R19 (Welcome), R39 (design directions); `docs/decisions.md` key screen layouts (paste review layout "a": side by side). Existing code: `LibraryStore+Import.swift` (`prepareImport`/`commitImport`, A29), `SongFileTypes.swift`, `MenuShortcuts.swift`, `FileCommands.swift`, `LibraryViews.swift` (empty state), `AnalyticsEvent.swift`, `IngestBody.swift` (VendorServices).

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

Every way a song comes in (clipboard, empty state, `⌘V` on the list, Import, drag and drop, `.crd`) lands in one review sheet that shows the deterministic result instantly and streams AI refinements in, with nothing saved before Accept; plus the analytics rows that measure it.

## Steps

0. **Design directions (R39 style):** 2-3 renders of the review sheet's AI marking (how AI-decided labels/metadata differ from rule-based conversion, the "Refining with..." line, the R69 footer note) within the chosen layout "a". Ryan picks before step 3. Do not design anything in the pending "Metadata entry and fast set building" area (spec 16.0).
1. **Entry points (R75):** `MenuShortcuts.newSongFromClipboard` = File > "New Song from Clipboard" `⌥⌘V` (the clash test must pass; also confirm in the running editor that `⌥⌘V` is not taken by the text system, report if it is); "Paste a Song" in the empty-library state; `⌘V` while the song list (not a text field, not the editor) has focus. Keyboard help (`?` overlay) lists the new item automatically via `MenuShortcuts.all`.
2. **Import routing:** `SongFileTypes.importExtensions` gains `crd` (update the comment that says "not accepted in 0.5"); `prepareImport` candidates are classified by `IngestPipeline` (`isAlreadyChordPro` -> direct import as today, A29; others -> review queue). Multiple conversion files queue one sheet at a time with **Skip Remaining** (open question 13, build to recommendation a); skipped files appear in the import summary with a reason.
3. **Review sheet** (`Packages/SegueUI/Sources/SegueUI/Paste/`): opens with `IngestResult` immediately; refinement runs through `AIServices` (P3-2) and streams in; the user can edit or Accept at any time (Accept cancels refinement); original left, result right; metadata fields (title, artist, key, capo, tempo, tags with starter suggestions from P3-6 if landed, else plain tags); unknown lines and bad tokens flagged; footer names the provider and shows the R69 note; during a show: deterministic only with the open question 12 behaviour (build to recommendation a). Accept -> `commitImport`; Cancel -> nothing written. No energy field and no AI tag guesses (R71). Undo of an accepted paste follows WS2a's Undo Import.
4. **Download offer** per open question 10 (build only option a until Ryan rules: no extra offer in the sheet).
5. **Welcome card + tip:** one card in the Welcome sheet's revisit cards ("Paste any chord sheet": what it does, that it stays on the Mac, a button to Settings > AI) and one TipKit tip on the empty library / song list pointing at `⌥⌘V`. Follow WS2b's TipKit rules (no tips during a show).
6. **Analytics (R74):** new `AnalyticsEvent` rows for `Segue.AI.pasteFinished`, `Segue.AI.modelDownload`, `Segue.AI.assistantUsed`, `Segue.AI.smartFilterUsed` and `featureUsed(.runThroughTimer)` with the enums/buckets in spec section 11 (exact names fixed here; every value <= 24 chars and allowlist-valid); `IngestBody` allowlist test extended; emit `pasteFinished` here (the other emitters belong to P3-3, P3-5, P3-6, P3-7: they call the cases you define). Correction bucket = edit distance between the AI-proposed labels/metadata and the accepted ones. Open question 15 (Hinglish flag): build to recommendation b (no flag).

## Tests

In-process SegueUI integration tests (real store, parser, temp library, `ScriptedProvider`): each entry point produces the sheet; Accept writes exactly the expected `.cho`; Cancel writes nothing; `.crd` and `.txt` go through review, `.cho` does not; queue + Skip Remaining; during-show path. Analytics: the rendered payloads of the new rows pass the allowlist. E2E `SeguePasteE2ETests`: clipboard paste -> sheet -> Accept -> song with correct sections; Cancel leaves the library unchanged; three files -> three sheets. Suites: `PasteReviewTests`, `AnalyticsVocabularyTests`.

## Files owned

`Packages/SegueUI/Sources/SegueUI/Paste/**`, `MenuShortcuts.swift`, `App/Commands/FileCommands.swift`, `Library/LibraryViews.swift` (empty state button + list `⌘V`), `Library/LibraryViewModel+Import.swift`, `SongFileTypes.swift`, the Welcome card file in `Onboarding/`, a new tip in the TipKit tips file, `AnalyticsEvent.swift` (+ its tests), `IngestBody.swift` allowlist tests, `UITests/SeguePasteE2ETests.swift`.

## Acceptance

All entry points work in both flavours; nothing reaches the library without Accept; the sheet never blocks on a model; new events pass the allowlist; `make quick` + `make gate` green.
