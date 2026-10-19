# P3-A - MLX in the shipped app (spike) and curated-model re-validation

Wave 1. **Status (2026-10-19): Part 1 done** (all seven proof points pass; `docs/research/phase3-mlx-in-app.md`, branch `spike/p3a-mlx-in-app`); the app-group store is accepted as proven (R100, no profile regeneration; App Store Connect acceptance is checked at the first real `make validate`). Its learnings are written into P3-3 and spec section 4.3. **Part 2 waits on Ryan's 10-20 pastes.** Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 4, 5, 12). Rulings: `docs/release/decisions.md` R61-R79 (especially R64, R66, R67, R77). Prior spike: `docs/research/phase3-spikes.md` and the harness in `research/phase3-spikes/`.

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

Prove, before anything ships, that MLX can live inside the real app: built by Tuist, sandboxed, hardened, archived as Release-AppStore, with the model store shared by both flavours. Then re-run the spike scorer on Ryan's own real pastes to decide whether Qwen3-4B-2507 4-bit gets locked (R64).

## Isolation

Part 1 changes `Project.swift`, entitlements and scripts experimentally: do it in a **git worktree** on a branch `spike/p3a-mlx-in-app` so the shared tree never breaks. What lands on main is the research doc, the eval folder tooling and the proven diff written up for P3-3 (P3-3 applies it). Throwaway models and build output stay gitignored.

## Part 1 - MLX inside the app (no Ryan input needed)

1. **Dependencies.** Add `mlx-swift-lm` 3.32.x (`MLXLLM`, `MLXLMCommon`, `MLXGuidedGeneration`) and the tokenizer (`swift-transformers` `Tokenizers`) through Tuist's `Tuist/Package.swift`, in a minimal `Packages/SegueAI` stub linked by **both** app targets. Do not use the `MLXHuggingFace` downloader (Segue downloads itself, R66). List every transitive pin and licence.
2. **Metal library.** Find how Tuist builds the MLX targets (static vs dynamic framework, `.external` product types) and make the MLX metallib land in `Segue.app/Contents/Resources` (or wherever mlx-swift resolves it); prove at run time that kernels load, not only that the file exists.
3. **Sandboxed, hardened Release-AppStore archive.** `make archive` with the MLX stub; launch the exported/dev-signed Release-AppStore app and run one real `SectionLabelTask`-shaped guided generation on Qwen3-4B (model copied into the store path by hand for the spike). Record: Metal shader compile under the sandbox, any hardened-runtime exception needed (expected none; any `allow-jit`/`disable-library-validation` need is a STOP-and-ask), console sandbox violations.
4. **App-group shared store (R67).** Add `com.apple.security.application-groups` with a team-prefixed group id (propose the exact id, e.g. `V6BM673U35.dev.ryandsilva.segue.models`, and check current Apple rules for Mac App Store app groups at source) to both flavours. Prove: the manually signed MAS build (profile "Segue Mac App Store") and the automatically signed Personal build both resolve the same container URL and read one model. Find out whether the MAS App ID and profile need the App Groups capability and a regenerated profile; if so, write the exact portal steps for Ryan (he runs them, R46 style) and STOP until done. Update `scripts/verify-archive.sh` check 4's allowed set on the branch and show it green.
5. **Deltas.** App size (`.pkg` and `.app`), clean and incremental build time, `make gate` time, launch time with and without SegueAI linked, memory with the model loaded and with `Memory.cacheLimit` = 512 MB.
6. **Privacy manifest and notices diff.** Which required-reason APIs the new dependencies use (scan their `PrivacyInfo.xcprivacy` files and symbols), and the full notices table rows `make docs-check` will demand.
7. **Write-up:** `docs/research/phase3-mlx-in-app.md` (results, exact Tuist/Project.swift diff, entitlements, verify-archive change, risks), plus a short "verified/unverified" update to `docs/research/phase3-ai.md`'s sandbox line.

## Part 2 - Re-validate the curated model on Ryan's pastes (R64)

Needs Ryan's 10-20 pastes in `research/phase3-eval/pastes/` (format in that folder's README). If they are not there, finish Part 1, report, and wait.

1. Build gold data for each paste: from its `.cho` when Ryan supplied one (sections give block labels; `{title}`, `{artist}`, `{key}`); otherwise draft gold yourself and ask Ryan to confirm it. Gold and results live in `research/phase3-eval/gold.local.json` and `research/phase3-eval/results/` (both gitignored: they name real songs).
2. Run the spike harness (`research/phase3-spikes/`, `mlxspike`/`fmspike` + `score.py`, generalised to read the local gold file) with the final design (split calls, hints, exact counts, bounded ints, no-free-whitespace grammar, one whitespace-bias retry) on Qwen3-4B-2507 and FM. Report label accuracy (headed/unheaded), title/artist/key, failures by kind, latency p50/p90, peak memory, split English/Hinglish.
3. **Bar: >= 90%** on section labels and on title/artist. Report pass/fail to the orchestrator with aggregate numbers only (no titles, no lyrics in any committed file or message). Pass -> the orchestrator asks Ryan to lock (a new ruling). Fail -> list failure kinds and propose the next candidates (Gemma 4 E2B, Qwen3.5-4B) for Ryan to rule on; swap nothing yourself.
4. Record the pinned revision (commit SHA) and per-file SHA256 + size for the candidate from the Hub API, for P3-3's manifest.

## Files owned

Branch/worktree: everything. On main: `docs/research/phase3-mlx-in-app.md`, the sandbox line in `docs/research/phase3-ai.md`, `research/phase3-eval/` tooling (scripts, never pastes), `research/phase3-spikes/` scorer generalisation.

## Hand-off

Pass/fail per Part 1 item, the proposed group id and whether Ryan must regenerate profiles, the diff for P3-3, the deltas table, the scorer result and lock recommendation, and the pinned revision + hashes.
