# Phase 0 adversarial review (2026-10-17)

Independent read-only review of eba5693..fcd823d. All findings reproduced or read-verified by the reviewer. Status tracked here; fixes land in the phase 0 hardening commit.

| # | Sev | Finding | Fix |
|---|---|---|---|
| 1 | high | `updateSong` overwrites external edits made while the editor is open (data loss) | compare on-disk hash with loaded hash before write; `LibraryError.conflict`; UI offers reload / overwrite / save as copy |
| 2 | med | one unreadable `.cho` (or failed orphan sidecar write) fails the whole library open | per-file load issues surfaced in UI, like `SetlistLoadIssue` |
| 3 | med | Finder-duplicated song can steal the original's ULID on cold launch ("foo copy" sorts first) | keeper = oldest createdAt / creation date, never the copy |
| 4 | med | open/refresh re-reads + hashes every file (2000 songs: ~4.5 s) | mtime+size short-circuit; batch index writes; scan off the launch path |
| 5 | med | Perform silently drops missing-song entries | warn before entering stage, list missing entries |
| 6 | med | AC3 (relaunch via bookmark) untested | LibraryLocation tests + second-launch E2E step |
| 7 | low | stage `present` re-entry nulls `app.live` | guard replace path |
| 8 | low | unreadable sidecar without id gets a new random id every launch | stable derived id, flagged unstable |
| 9 | low | lone `\r` line endings break idempotence / parse as one line | `LineEnding.cr`, corpus fixture |
| 10 | low | keystrokes during save dropped; external delete discards unsaved edits | lock editor while saving; keep editor + offer save as new |
| 11 | low | non-UTF-8 files edited lossy | non-UTF-8 opens read-only with reason |
| 12 | low | 5 ms parser benchmark is a flake risk | 50 ms catastrophic guard in serial suite |
| 13 | low | rebuildIndex failure leaves closed pool; Cmd-N/R live during stage; remember() failure state; search spinner | as described in review |
