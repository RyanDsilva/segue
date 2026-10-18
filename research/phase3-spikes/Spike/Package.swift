// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Spike",
    platforms: [.macOS("26.4")],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(name: "SpikeCore"),
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
