# Phase 3 AI research (2026-10-17)

Primary sources only. **V** = verified (source opened), **U** = unverified. Local machine: macOS 26.6.2, Xcode 26.6, MacOSX26.5 SDK. macOS 27.0 shipped 2026-09-14, and Xcode 27.1 is current (V, https://developer.apple.com/news/releases/). macOS 27 is not installed here.

## 1. Apple Foundation Models (FM)

**Installed SDK (26.5): checked against `FoundationModels.swiftinterface`, the authoritative source:**
- `SystemLanguageModel.contextSize: Int` is `@backDeployed(before: macOS 26.4)`, and the back-deployed body returns the constant `4096`. `tokenCount(for:)` overloads exist for prompt, `Instructions`, `[Tool]`, `GenerationSchema` and transcript entries, macOS 26.4+ only. **V (SDK)**
- There is no `LanguageModel` protocol: `SystemLanguageModel` is a `final class` and `LanguageModelSession.init(model: SystemLanguageModel, ...)`. No PCC types and no image input. **V (SDK)**
- `GenerationError` cases are `exceededContextWindowSize`, `assetsUnavailable`, `guardrailViolation`, `unsupportedGuide`, `unsupportedLanguageOrLocale`, `decodingFailure`, `rateLimited`, `concurrentRequests` and `refusal`. **V (SDK)**
- `Availability.UnavailableReason` cases are `deviceNotEligible`, `appleIntelligenceNotEnabled` and `modelNotReady`. Other members: `supportedLanguages`, `supportsLocale(_:)`, `UseCase.general/.contentTagging`, `Guardrails.default/.permissiveContentTransformations`, `prewarm(promptPrefix:)` and `isResponding`. **V (SDK)**
- Guides: `.anyOf([String])`, `.constant`, regex `.pattern`, numeric `.range/.minimum/.maximum`, and array `.count/.minimumCount/.maximumCount/.element`. `DynamicGenerationSchema` is supported. `respond(..., includeSchemaInPrompt:)`, `streamResponse` with `PartiallyGenerated`. `GenerationOptions` has sampling `.greedy` or `.random(top:/probabilityThreshold:, seed:)`, `temperature` and `maximumResponseTokens`. **V (SDK)**

**macOS 27 / WWDC26:**
- **Context size.** The docs article still says "a context window of 4096 tokens per session" (V, https://developer.apple.com/documentation/foundationmodels/managing-the-context-window). The WWDC26 "What's new" demo prints `contextSize // 8192` (V, https://developer.apple.com/videos/play/wwdc2026/241/). A secondary summary claimed "8K on newer devices", but I could not confirm that wording: **U**. Treat the value as hardware-dependent and read it at runtime.
- **`LanguageModel` / `LanguageModelExecutor` protocols** (macOS 27+) let any model back a `LanguageModelSession`. `SystemLanguageModel` and `PrivateCloudComputeLanguageModel` conform to them. V: https://developer.apple.com/documentation/foundationmodels/languagemodel.md, https://developer.apple.com/videos/play/wwdc2026/339/
- **Unified `LanguageModelError`** (macOS 27+) replaces `GenerationError`, which is now marked deprecated and is used on 26.x. It adds `timeout` and `unsupportedCapability`. Documented `rateLimited` behaviour: "too many requests in a short window ... recover by spacing your requests". V: https://developer.apple.com/documentation/foundationmodels/languagemodelerror.md, https://developer.apple.com/documentation/foundationmodels/languagemodelerror/ratelimited(_:).md. Claim that background apps are throttled harder: **U**.
- **Guardrails.** iOS 26.4 reduced false positives and iOS 27 continues that work (V, WWDC26-241). `permissiveContentTransformations` "only works for generating a string value. When you use guided generation, the framework runs the default guardrails". So lyrics that mention violence, drugs or sex can still throw `guardrailViolation` or `refusal` inside `@Generable` calls (V, https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output.md). How often real lyrics trip them: **U**, needs the spike.
- **Private Cloud Compute (PCC) for third-party apps.** Requirements: macOS 27+, a managed entitlement `com.apple.developer.private-cloud-compute`, enrolment in the App Store Small Business Program, under 2M first-time downloads, App Store/TestFlight/ad hoc distribution, and a network connection. Users get a daily per-iCloud-account quota (iCloud+ raises it). Context is 32K, with reasoning levels. V: https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute.md, https://developer.apple.com/private-cloud-compute/
- **Image input** (`Attachment`, `ImageAttachmentContent`), dynamic profiles and an Evaluations framework are new in 27 (V, https://developer.apple.com/documentation/foundationmodels.md). They matter for phase 4 (PDF/photo import), not phase 3.
- **Languages.** "Same model understands ... any language that Apple Intelligence supports". FM checks the prompt language and throws `unsupportedLanguageOrLocale`. Guardrails apply only to supported languages (V, https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models.md). The Apple Intelligence language list for macOS 27 does **not** include Hindi (V, https://support.apple.com/en-us/121115). Apple's AFM-3 report evaluates Hindi among its locales (V, https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models), but evaluation is not shipped support. Behaviour on romanized Hindi is **U**: it could pass as English, throw `unsupportedLanguageOrLocale`, or quietly "correct" spellings. No primary source covers transliterated or code-mixed text.

## 2. MLX Swift

- **Versions.** `ml-explore/mlx-swift` **0.32.3** and `ml-explore/mlx-swift-lm` **3.32.3** (2026-09-30), both MIT. `mlx-swift-examples` now only holds example apps; the library code lives in `mlx-swift-lm`. V: `gh api repos/ml-explore/{mlx-swift,mlx-swift-lm}/releases`, https://github.com/ml-explore/mlx-swift-lm
- **Package layout.** The package has a macOS 14 floor. Products: `MLXLLM`, `MLXLMCommon`, `MLXHuggingFace` (macros `#huggingFaceLoadModelContainer`, `#hubDownloader`), `MLXGuidedGeneration` and `MLXFoundationModels`. Downloader and tokenizer are pluggable (`swift-huggingface` 1.0.0 plus `swift-transformers`). V: https://github.com/ml-explore/mlx-swift-lm/blob/main/Package.swift, README
- **Constrained decoding.** `MLXGuidedGeneration` masks logits so output conforms to a JSON Schema or EBNF (XGrammar). It works with any MLX model on macOS 14+. V: https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXGuidedGeneration/README.md
- **FM bridge.** `MLXFoundationModels` provides `MLXLanguageModel: FoundationModels.LanguageModel`, so `LanguageModelSession(model:)` works with `@Generable`, which is grammar-constrained automatically, plus tools and streaming. Capabilities are declared explicitly (`.guidedGeneration` by default; `.toolCalling`, `.reasoning`, `.vision`). It exposes `availability` (`.available/.downloading/.unavailable`). It **requires the macOS 27 SDK and runtime** and compiles to an empty module otherwise. V: https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXFoundationModels/README.md
- **Cache location.** In `swift-huggingface`, `CacheLocationProvider.environment` resolves `HF_HUB_CACHE`, then `HF_HOME/hub`, then `~/.cache/huggingface/hub`. Sandboxed apps fall back to the container's **`Library/Caches/huggingface/hub`, which is purgeable**. `.fixed(directory:)` overrides it. V: https://github.com/huggingface/swift-huggingface/blob/main/Sources/HuggingFace/Shared/CacheLocationProvider.swift
- **Sandbox.** Downloading needs `com.apple.security.network.client` (V, https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client.md). Running MLX inside an App Sandbox, including Metal kernel compilation: **V** (P3-A, 2026-10-19): an archived, sandboxed, hardened Release-AppStore build compiled the kernels, loaded Qwen3-4B from the app-group container and ran guided generation with no sandbox violation and no hardened-runtime exception; App Store Connect validation of the app-group entitlement is still **U**. See `phase3-mlx-in-app.md`.
- **Memory and latency.** Apple measured 4096-token prompts on 24GB M4/M5: Qwen 8B 4-bit uses 5.61 GB, Qwen 1.7B BF16 uses 4.40 GB, and M5 gives a 3.6-4x faster time-to-first-token than M4 (V, https://machinelearning.apple.com/research/exploring-llms-mlx-m5). Extrapolated for a 2-4B 4-bit model: about 2-3.5 GB RAM and sub-second TTFT for a ~1K prompt on M-series. This is **U**; the spike must measure it.

## 3. Candidate models

Sizes are summed `mlx-community` repo blobs; licences are read from the upstream HF `cardData` (V, `https://huggingface.co/api/models/<id>`).

| Model (mlx-community 4-bit) | Disk | Licence (upstream) | Notes |
|---|---|---|---|
| Qwen3-4B-Instruct-2507-4bit | 2.28 GB | Apache-2.0 | Non-thinking only, so no `<think>` latency; `qwen3` arch in `LLMRegistry` (V card) |
| Qwen3.5-2B-MLX-4bit | 1.75 GB | Apache-2.0 | Thinks by default (disable it); vision-language model; "201 languages"; `LLMRegistry.qwen3_5_2b_4bit` (V card, registry) |
| Qwen3.5-4B-MLX-4bit | 3.06 GB | Apache-2.0 | As above, larger |
| gemma-4-e2b-it-4bit | 3.58 GB | Apache-2.0, plus Google prohibited-use policy linked | 2.3B effective; carries audio and vision towers; 140+ languages; `LLMRegistry.gemma4_e2b_it_4bit` (V, https://ai.google.dev/gemma/docs/gemma_4_license) |
| Phi-4-mini-instruct-4bit | 2.18 GB | MIT | Card warns "trained primarily on English" (V) |
| Ministral-3-3B-Instruct-2512-4bit | 2.78 GB | Apache-2.0 | |
| SmolLM3-3B-4bit | 1.75 GB | Apache-2.0 | Language list has no Hindi |
| Llama-3.2-3B-Instruct-4bit | 1.82 GB | Llama 3.2 Community | Must ship the licence copy and show "Built with Llama", plus AUP; lists `hi` (V, github.com/meta-llama/llama-models/.../llama3_2/LICENSE) |
| gemma-3-4b-it | - | Gemma terms (gated) | Superseded by Gemma 4 |

**Recommend evaluating:**
1. **Qwen3-4B-Instruct-2507** - strong quality per GB and no thinking overhead.
2. **Qwen3.5-2B** - the smallest download, newest, and broadest language coverage.
3. **Gemma 4 E2B** - an independent model family under Apache-2.0.

All three are permissive for App Store distribution: ship the licence text and model attribution in Settings > AI > Licences. Avoid Llama for curated use because of the attribution/AUP obligations. Note that the `mlx-community/gemma-3-4b-it-qat-4bit` card declares `license: other / qwen`, base InternVL. That is mislabelled metadata.

## Spec impacts

1. **Budget from runtime values, not "~2,500 tokens".** Compute `budget = contextSize - tokenCount(instructions) - tokenCount(schema) - maxResponseTokens - margin`. On 26.0-26.3, `tokenCount` is missing and `contextSize` returns 4096, so fall back to a conservative chars/3 estimate. Set `includeSchemaInPrompt: false` where the prompt already shows the shape.
2. **The model never echoes lyrics.** `@Generable` outputs refer to blocks or lines **by index**, for example `[{blockIndex, label}]`, and line classes by line number. Lyrics then cannot be respelled by construction, output tokens shrink, and output-side guardrail hits mostly disappear. The lyric guard stays as a backstop.
3. **Routing additions.** Add `unsupportedLanguageOrLocale`, `guardrailViolation`, `refusal`, `rateLimited` and `concurrentRequests` as typed fallback reasons, so FM falls to MLX and then to deterministic. Use one fresh session per call, never concurrent calls on one session. Map both `GenerationError` (26) and `LanguageModelError` (27). Add a cheap **romanized-Hindi heuristic** (stop-list hit rate) that can route straight to MLX, gated by spike 2a results.
4. **The MLX adapter uses constrained decoding, not parse-and-retry.** Use `MLXGuidedGeneration` with a JSON Schema on macOS 26. Keep parse-and-retry only for models whose tokenizer XGrammar can't load.
5. **Port shape.** Keep Segue's own `LanguageModelProvider`, because the app targets macOS 26 and needs `ScriptedProvider`. On macOS 27, the FM and MLX adapters can share one implementation via `LanguageModelSession(model: SystemLanguageModel | MLXLanguageModel)` and the same `@Generable` types. This removes the separate JSON schema. That path is only available if the deployment target becomes macOS 27 (open question A).
6. **Model storage.** Configure `HubCache(location: .fixed(<App Support>/Models))`. The library default is purgeable Caches, which contradicts the spec. Add the `network.client` entitlement. The licence shown for a custom model must come from the **upstream `base_model` card** as well as the mlx-community card, which can be wrong.
7. **PCC is out of scope.** It needs macOS 27, network access, a paid team, Small Business Program enrolment and a managed entitlement, which conflicts with "on-device, offline, free" and the Personal Team. Record it as rejected for now.
8. **NL picks < 1 s.** Call `prewarm(promptPrefix:)` when the pick field gets focus, use `.greedy` sampling, and use small `.anyOf` guides for keys, tags and proficiency drawn from the library's actual values.
9. **Eval set.** Consider the macOS 27 Evaluations framework only if the target moves to 27. Otherwise keep the custom eval target.

## Open questions (need a decision)

- **A.** Raise the minimum OS to macOS 27? That unlocks the `LanguageModel` protocol, `MLXLanguageModel`, `LanguageModelError` and image input, and drops the dual error and schema paths. The cost: this dev machine and any macOS 26 users. Alternatively, stay on 26 with `#available` branches.
- **B.** If FM guardrails or the language check reject romanized-Hindi songs often in spike 2a, should Hindi-detected songs go **MLX-first** by default, or deterministic-only?
