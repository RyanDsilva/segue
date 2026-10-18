import ProjectDescription

/// Tuist is used local-only (decisions.md): open-source `tuist generate`, no cloud account,
/// no caching. The version is pinned in `.mise.toml`.
let tuist = Tuist(
    project: .tuist(
        compatibleXcodeVersions: [.upToNextMajor("26.0"), .upToNextMajor("27.0")],
        generationOptions: .options(
            disablePackageVersionLocking: false,
        ),
    ),
)
