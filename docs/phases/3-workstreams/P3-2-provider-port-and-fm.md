# P3-2 - Provider port, Foundation Models adapter, tasks and routing

Wave 2 (after P3-1). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 3, 4, 4.1, 4.2, 14). Rulings: `docs/release/decisions.md` R61-R103 (R62, R63, R69, R77; R92 set-request routing, R93 AI toggle, R94 per-call load, R95 no paste during a show, R101 converter rulings). Measurements: `docs/research/phase3-spikes.md` sections 2 and 5.3 (validated prompt/schema design) and the spike code in `research/phase3-spikes/Spike/` (`fmspike`, `SpikeCore/Types.swift`).

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

The one AI seam: Core port types, typed tasks, a config-driven router with typed fallback reasons, a `ScriptedProvider` that replays recorded real outputs, and the Foundation Models adapter in a new `Packages/SegueAI` package linked by both flavours. After this workstream, a paste is refined by FM when available, and every test runs offline through `ScriptedProvider`.

## Deliverables

0. **Converter follow-ups (R101, from P3-1; do these first, one commit):** see `P3-1-deterministic-pipeline.md` section "Rulings on the built converter and follow-ups": an unheaded block repeating an earlier block's lyrics -> both labelled Chorus (expected 92% -> 99% deterministic label accuracy on the gold set); pin "with a capo, `{key}` is the shapes key" and "unknown pasted lines -> `{comment}`" with fixtures; update the expected `.cho` files and `gold.json`; report the new accuracy. Keep P3-1's accepted defaults (detected keys never written into the `.cho`; credits mapping; chord over a space attaches to the next word).
1. **SegueCore module `ModelPort`:** `LanguageModelProvider`, `ProviderID`, `ProviderAvailability` (with `UnavailableCause` mirroring FM's `UnavailableReason` + `notInstalled` + `duringShow`), typed `ProviderError`, `ModelTask` protocol, the four tasks and their outputs (`SectionLabelTask`, `MetadataTask`, `AmbiguousLineTask`, `SetRequestTask`), `CallMetrics` (latency, prompt/output tokens, retries) used only for analytics buckets (no local metrics store, R74), and a **`Router`** that runs a task down an ordered provider list (default R63: curated MLX -> FM -> none, for `SetRequestTask` too per R92), returns the deterministic result without calling anything when the AI toggle is off (R93; the toggle's storage is P3-3's, the router reads an injected flag), falls through on the typed errors listed in spec 4.1, spaces one retry on `rateLimited`/`busy`, and reports which provider answered and why others did not. The order comes from a bundled config file per task.
2. **`ScriptedProvider`:** replays recorded outputs from `Tests/Fixtures/paste/recorded/<provider>/<fixture>.json`, keyed by task kind + a stable hash of the task input; an unknown key throws (tests fail loudly). Can also script failures (each `ProviderError`) for routing tests.
3. **Refinement merge in `Ingest`:** `IngestPipeline.apply(_:)` (seam defined by P3-1): labels only for unheaded blocks (headed labels always come from code), metadata only where code found none, model key only when `KeyDetector` is ambiguous and the key is in the top two (and, like every detected key, offered in the review sheet as a suggestion, never written into the `.cho` unless the user picks it, R101), line classes for unknown lines; then **LyricGuard** - a refinement that would change any lyric token is rejected for that block and logged as a diagnostic.
4. **New package `Packages/SegueAI`** (Swift 6, strict settings like SegueCore, macOS 26 floor), module `FoundationModelsAdapter` plus `GenerableTasks`: one `@Generable` wire type per task with **no optionals**, `.anyOf` enums for labels/keys/tags, `DynamicGenerationSchema` exact counts for labels, `.maximumCount` on every other array; mapping to the Core outputs; post-processing ("Unknown" -> empty, artist == title -> empty). Expose `schemaJSON(for:)` (encode `GenerationSchema`) for P3-3's MLX adapter, so there is one schema source.
5. **FM adapter:** fresh session per call, `.greedy`, prompts from the spike's final design (split labels/metadata calls, deterministic hints in the prompt, metadata call skipped when there is no candidate), runtime budget (`contextSize`, `tokenCount` behind `#available(macOS 26.4, *)`, chars/3 fallback), chunking on block boundaries with hints only when the router says MLX is absent, mapping of every `GenerationError` to `ProviderError`. Availability -> the R69 causes.
6. **Wiring:** add SegueAI to `Project.swift` for **both** app targets and to `make test-packages` / `make quick` (a fourth package). App-side composition in a new `Packages/SegueUI/Sources/SegueUI/App/AppModel+AI.swift` (`AIServices`: router, providers, availability observation) that P3-3, P3-4 and P3-7 consume; keep the edit to `AppModel`/`AppDependencies` to the one property that holds it.
7. **R69 copy:** the availability note strings and the "Open System Settings" deep link, in one place (`AIAvailabilityCopy`), used by P3-3/P3-4/P3-7.
8. **Recordings:** a first set of FM recordings for all golden fixtures, produced by a small manual runner in SegueAI (P3-3 later folds it into `make eval-ai`). Never run from tests.

## Tests

Integration through `IngestPipeline` + `ScriptedProvider`: each fixture with FM recordings -> merged result -> expected refined `.cho`; routing table tests (each error -> next provider -> deterministic); lyric-guard rejection with a scripted respelled/translated output; budget/chunk selection with a 40-block fixture. Suites: `ModelPortRoutingTests`, `IngestRefinementTests`, `FoundationModelsAdapterMappingTests` (pure mapping only; no real FM).

## Files owned

`Packages/SegueCore/Sources/ModelPort/**`, `Packages/SegueCore/Sources/Ingest/**` (P3-1 has landed: step 0 edits its files, the refinement merge adds new ones), `Packages/SegueCore/Tests/IngestTests/**` and `Tests/Fixtures/paste/*.cho` + `gold.json` for step 0, `Packages/SegueCore/Tests/ModelPortTests/**`, `Tests/Fixtures/paste/recorded/**`, `Packages/SegueAI/**` (FM parts; P3-3 adds MLX), `Project.swift` (SegueAI dependency only, wave 2), `Makefile` (package list), `AppModel+AI.swift`, the one-line `AppModel` property.

## Acceptance

Step 0's fixtures pass with the new Chorus labels and the accuracy is reported; paste fixtures refine through FM recordings with zero lyric/chord change; every routing path covered; both flavours build with SegueAI; `make quick` + `make gate` green.
