// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Spike",
    platforms: [.macOS("26.4")],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
        // P3-A part 2: the app's real deterministic pipeline (P3-1), compiled from symlinks
        // into Packages/SegueCore/Sources (Ingest is not a SegueCore product).
        .package(url: "https://github.com/AudioKit/Tonic", exact: "2.1.2"),
    ],
    targets: [
        .target(name: "ChordPro", dependencies: [.product(name: "Tonic", package: "Tonic")]),
        .target(name: "MusicTheory", dependencies: [.product(name: "Tonic", package: "Tonic")]),
        .target(name: "Ingest", dependencies: ["ChordPro", "MusicTheory"]),
        .target(name: "SpikeCore", dependencies: ["Ingest", "MusicTheory"]),
        .executableTarget(name: "fmspike", dependencies: ["SpikeCore"]),
        .executableTarget(
            name: "mlxspike",
            dependencies: [
                "SpikeCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]),
    ]
)
