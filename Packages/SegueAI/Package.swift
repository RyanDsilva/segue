// swift-tools-version: 6.2
//
// SegueAI: the AI provider adapters behind SegueCore's ModelPort (docs/phases/
// 3-ai-entry-and-assistant.md section 4, R77). Linked by BOTH app flavours. P3-2 added the
// Foundation Models side (`GenerableTasks`, `FoundationModelsAdapter`); P3-3 adds the local
// model store (`ModelStore`), the MLX provider (`MLXAdapter`, MLX-free logic) and its MLX
// binding (`MLXEngine`), and the eval runner (`make eval-ai`).
//
// MLX and the tokenizer are pinned to the SAME exact versions as `Tuist/Package.swift`. No
// `MLXHuggingFace`: Segue downloads models itself (R66) and loads tokenizers from the model
// folder. Tests stay MLX-free: SwiftPM's command line cannot build MLX's Metal library, so
// no test target depends on `MLXEngine`, and real inference runs only through `make eval-ai`.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SegueAI",
    platforms: [.macOS("26.0")],
    products: [
        .library(
            name: "SegueAI",
            targets: [
                "GenerableTasks", "FoundationModelsAdapter", "ModelStore", "MLXAdapter",
                "MLXEngine",
            ],
        ),
        // The eval's fixture runner and scorer: `make eval-ai` and Personal's "Check this
        // model" (R62). Not linked by the App Store flavour.
        .library(name: "SegueAIEval", targets: ["AIEval"]),
        // `make eval-ai` (manual, never run by tests or gates): real FM and MLX over the paste
        // fixtures, scores against the baseline, and with RECORD=1 the ScriptedProvider
        // recordings. Built by xcodebuild, which builds MLX's Metal library.
        .executable(name: "segue-eval", targets: ["segue-eval"]),
    ],
    dependencies: [
        .package(path: "../SegueCore"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.5"),
    ],
    targets: [
        // One @Generable wire type per task (no optionals, .anyOf enums, exact or maximum
        // counts), its mapping to the Core output, and the schema export MLX reuses.
        .target(
            name: "GenerableTasks",
            dependencies: [.product(name: "SegueCore", package: "SegueCore")],
            swiftSettings: strictSettings,
        ),
        .target(
            name: "FoundationModelsAdapter",
            dependencies: [
                "GenerableTasks",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
        // The curated model catalog (a bundled JSON), the downloader (R54 headers, resume,
        // per-file SHA256) and the app-group store shared by both flavours (R67, R100).
        .target(
            name: "ModelStore",
            dependencies: [.product(name: "SegueCore", package: "SegueCore")],
            resources: [.copy("Resources/curated-models.json")],
            swiftSettings: strictSettings,
        ),
        // The MLX provider without MLX: no-free-whitespace grammars, prompts, residency
        // (load per paste or request, R94), timeout, retry and error mapping, all behind the
        // `GuidedEngine` seam that `MLXEngine` implements.
        .target(
            name: "MLXAdapter",
            dependencies: [
                "GenerableTasks",
                "ModelStore",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
        // The MLX binding: loads a model folder with `LLMModelFactory.shared` and Segue's
        // own tokenizer loader, and runs one grammar-constrained greedy generation.
        .target(
            name: "MLXEngine",
            dependencies: [
                "MLXAdapter",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: strictSettings,
        ),
        // The eval's MLX-free half: fixtures and gold, the pipeline run, the spike metrics.
        .target(
            name: "AIEval",
            dependencies: [.product(name: "SegueCore", package: "SegueCore")],
            resources: [.copy("Resources/baseline.json")],
            swiftSettings: strictSettings,
        ),
        .executableTarget(
            name: "segue-eval",
            dependencies: [
                "AIEval",
                "FoundationModelsAdapter",
                "MLXAdapter",
                "MLXEngine",
                "ModelStore",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
        .testTarget(
            name: "FoundationModelsAdapterMappingTests",
            dependencies: [
                "GenerableTasks",
                "FoundationModelsAdapter",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
        .testTarget(
            name: "ModelStoreTests",
            dependencies: [
                "AIEval",
                "ModelStore",
                "MLXAdapter",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
    ],
)
