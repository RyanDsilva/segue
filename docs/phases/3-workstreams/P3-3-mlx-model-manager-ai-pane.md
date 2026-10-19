# P3-3 - MLX adapter, model manager and the Settings > AI pane

Wave 3 (after P3-A and P3-2). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 4, 5, 10, 12, 14). Rulings: `docs/release/decisions.md` R61-R79 (R62, R64, R66, R67, R68, R69, R73), R54 (header stripping), R15 (deletes to Trash). Inputs: P3-A's `docs/research/phase3-mlx-in-app.md` (proven Tuist diff, group id, metallib placement, pinned revision + hashes), `docs/research/phase3-spikes.md` section 3.

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

The curated local model works end to end in both flavours: downloaded on request from Hugging Face with integrity checks, stored once in the shared app-group store, run through guided generation, shown and managed in a new sixth Settings pane. Personal adds Advanced custom models.

## Deliverables

1. **Apply P3-A's proven integration** to main: MLX dependencies in SegueAI, `Project.swift` (only P3-3 edits it in wave 3), metallib placement, app-group entitlement in both flavours' entitlements files, `scripts/verify-archive.sh` check 4 allowed set (same commit as the entitlements), notices rows in `THIRD_PARTY_NOTICES.md` and the licence texts the bundle ships in Resources (the in-app Acknowledgements window was removed 2026-10-18; `make verify-appstore` checks the bundled notices) so `make docs-check` passes. If P3-A's app-group proof failed, STOP: open question 8 needs Ryan's ruling.
2. **MLX adapter** (`Packages/SegueAI/Sources/MLXAdapter`): `MLXGuidedGeneration` with the schema from P3-2's `schemaJSON(for:)` plus exact counts and bounded ints; no-free-whitespace grammar; one retry with whitespace bias on `incompleteOutput`; `Memory.cacheLimit` 512 MB; greedy; load/unload per open question 11 (build to recommendation a: load when the paste sheet or assistant opens, unload 2 min after last use and **immediately when a show starts**; refuse to load while a show runs). Errors mapped to `ProviderError`.
3. **ModelStore** (`Packages/SegueAI/Sources/ModelStore`): the curated manifest (repo, pinned revision, per-file size + SHA256, licence id + upstream link, RAM need) as a bundled JSON; downloader on `URLSession` with resume data, cancel, progress, free-disk check before start, per-file SHA256 verification (mismatch -> delete + fail), **R54 headers** (no `Accept-Language`, fixed `Segue/<version>` User-Agent, verified on the CDN redirect hop), store path in the app-group container `Library/Application Support/Models/<repo>/<revision>/`, `isExcludedFromBackup`, a cross-flavour file lock during download, delete per open question 16 (build to recommendation b, direct removal after a confirmation, until Ryan rules), state observable by the UI.
4. **Settings > AI pane** (`Packages/SegueUI/Sources/SegueUI/Settings/AISettingsView.swift`, `SegueSettingsView.swift` gets a sixth `Pane.ai` after Live; only P3-3 edits the Settings host): Apple Intelligence status with R69 note + Open System Settings; the curated model card (name, "candidate" until R64 locks it, Apache-2.0 + link, 2.28 GB, about 3 GB RAM, free disk, Download / progress / Cancel / Delete); low-RAM warning under 16 GB (R68, never blocks); AI preference per open question 9 (build to recommendation b, one toggle, default on, until Ryan rules); Reset All Settings resets the AI prefs and keeps models (R73, extend the existing reset path and its test). Accessibility identifiers `segue.settings.ai.*`.
5. **Advanced (Personal only, R62)**: repo id field, Hub card fetch (size, upstream `base_model` licence), download on click, "Check this model" (runs the bundled original fixtures, shows score next to the curated model's, never blocks), one active MLX model. Placement per open question 7 (build to recommendation a, `SeguePersonalModules`, and extend `make verify-appstore` so no Advanced symbol reaches the App Store flavour) once Ryan rules; until then build the curated path only.
6. **Router config:** the MLX provider joins the default order (curated MLX -> FM -> none) when installed.
7. **`make eval-ai`** (manual, never in `make check`/`make gate`): an xcodebuild-built eval runner (SwiftPM CLI does not build the metallib) that runs FM and MLX over the golden fixtures and `research/phase3-eval/pastes/` (if present), writes jsonl + a score summary (spike metrics), compares with a stored baseline (aggregate numbers only, no titles), and with `RECORD=1` refreshes `ScriptedProvider` recordings for the committed fixtures only (never for Ryan's pastes).

## Tests

Downloader against a local HTTP test server (resume, cancel, checksum mismatch, disk-full, redirect, header assertions); store path and backup exclusion; pane UI in-process tests (no model, downloading, installed, low RAM, FM unavailable per reason); reset-keeps-models; E2E `SegueAISettingsE2ETests`: no model -> size and licence shown, nothing downloads without a click (download stubbed via a Debug-only test hook). Suites: `ModelStoreTests`, `AISettingsTests`. MLX inference itself is covered only by `make eval-ai`.

## Files owned

`Packages/SegueAI/Sources/MLXAdapter/**`, `Packages/SegueAI/Sources/ModelStore/**`, eval runner, `Project.swift` (wave 3), `App/Segue.entitlements`, `App/SegueAppStore.entitlements`, `App/Segue-Debug.entitlements` (if needed), `scripts/verify-archive.sh`, `scripts/verify-appstore.sh` (Advanced check), `Makefile` (`eval-ai`), `THIRD_PARTY_NOTICES.md` + the bundled licence texts, `Settings/AISettingsView.swift`, `Settings/SegueSettingsView.swift`, the reset path.

## Acceptance

Both flavours download, verify and share one model; a paste refines through MLX in the archived sandboxed build; verify-archive green; no download without a click; `make eval-ai` reproduces the spike numbers within noise; `make quick` + `make gate` green.
