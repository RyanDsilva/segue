import Foundation

// Downloadable local models (spec section 5, R64, R66, R67): the value types and the port the
// Settings > AI pane drives. `Packages/SegueAI`'s `ModelStore` implements the port; the UI and
// its tests see only these types, so SegueUI never links MLX.

/// One downloadable model, pinned: a config entry, never code. The curated catalog is a bundled
/// JSON list of these (`ModelStore/Resources/curated-models.json`), so swapping the curated
/// model, or adding a larger "quality" entry beside it, is a data change.
public struct LocalModelManifest: Sendable, Hashable, Codable, Identifiable {
    /// One file the loader opens, with its pinned size and digest.
    public struct File: Sendable, Hashable, Codable {
        /// Path inside the repo (`model.safetensors`).
        public var name: String
        public var size: Int64
        /// Lowercase hex SHA256 of the file (the Hub's LFS digest, or a local hash of the
        /// pinned revision). Every curated file has one.
        public var sha256: String?
        /// The Hub's git blob id (SHA1 of `blob <size>\0<content>`): the only digest the Hub
        /// publishes for a non-LFS file, used for custom models (Personal, R62).
        public var gitBlobID: String?

        public init(name: String, size: Int64, sha256: String? = nil, gitBlobID: String? = nil) {
            self.name = name
            self.size = size
            self.sha256 = sha256
            self.gitBlobID = gitBlobID
        }
    }

    /// The upstream licence (the base model's card, not only the mlx-community conversion).
    public struct License: Sendable, Hashable, Codable {
        /// SPDX-style id (`apache-2.0`).
        public var id: String
        /// What the pane shows (`Apache-2.0`).
        public var name: String
        /// The upstream model card or licence text.
        public var url: URL
        /// The upstream repo the weights were converted from (`Qwen/Qwen3-4B-Instruct-2507`).
        public var upstreamRepo: String

        public init(id: String, name: String, url: URL, upstreamRepo: String) {
            self.id = id
            self.name = name
            self.url = url
            self.upstreamRepo = upstreamRepo
        }
    }

    /// How settled the choice of this model is (R64).
    public enum Status: String, Sendable, Hashable, Codable {
        /// A stand-in while the choice is open (the bake-off for low-memory Macs runs).
        case provisional
        /// The candidate R64 names, not locked yet.
        case candidate
        /// Locked by Ryan's ruling.
        case locked
        /// Added by the user under Advanced (Personal only, R62).
        case custom
    }

    /// Where an entry sits in the curated catalog: the default model, or an optional larger
    /// one for Macs with memory to spare. The catalog ships one entry today.
    public enum Role: String, Sendable, Hashable, Codable {
        case standard
        case quality
        case custom
    }

    /// Stable id for preferences and analytics-free bookkeeping (`qwen3-4b-2507-4bit`).
    public var id: String
    /// What the pane shows (`Qwen3 4B Instruct`).
    public var displayName: String
    public var status: Status
    public var role: Role
    /// Hugging Face repo id (`mlx-community/Qwen3-4B-Instruct-2507-4bit`).
    public var repo: String
    /// The pinned commit revision (40 hex characters).
    public var revision: String
    /// The files the loader opens; nothing else is downloaded.
    public var files: [File]
    public var license: License
    /// Peak memory while the model works, in bytes (shown, and the basis of the low-RAM note).
    public var memoryBytes: Int64

    public init(
        id: String,
        displayName: String,
        status: Status,
        role: Role,
        repo: String,
        revision: String,
        files: [File],
        license: License,
        memoryBytes: Int64,
    ) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.role = role
        self.repo = repo
        self.revision = revision
        self.files = files
        self.license = license
        self.memoryBytes = memoryBytes
    }

    /// The model the MLX provider names in `ProviderID.mlx`.
    public var ref: ModelRef {
        ModelRef(repo: repo, revision: revision)
    }

    /// The download size: every file.
    public var downloadBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    /// Whether every file carries a digest, so the download can be verified. A manifest
    /// without one is refused by the store.
    public var isVerifiable: Bool {
        !files.isEmpty && files.allSatisfy { $0.sha256 != nil || $0.gitBlobID != nil }
    }
}

/// The curated catalog file.
public struct LocalModelCatalog: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var models: [LocalModelManifest]

    public init(schemaVersion: Int = 1, models: [LocalModelManifest]) {
        self.schemaVersion = schemaVersion
        self.models = models
    }

    public static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

/// Why a download stopped (the `Segue.AI.modelDownload` result buckets, spec 11).
public enum ModelDownloadFailure: String, Sendable, Hashable, Codable, CaseIterable {
    /// Offline, a server error or an unexpected response. The partial files are kept.
    case network
    /// A file's digest did not match the manifest: it was deleted.
    case checksum
    /// Not enough free space, before the start or while writing.
    case disk
    case other
}

/// Where one model stands in the shared store.
public enum LocalModelState: Sendable, Hashable {
    case notInstalled
    /// Downloading now; bytes include files finished earlier and resumed partial data.
    case downloading(received: Int64, total: Int64)
    /// Stopped by Cancel with partial data kept; Download resumes it.
    case paused(received: Int64, total: Int64)
    /// Hashing files already on disk (a resumed or adopted download) before the transfer.
    case verifying
    case installed
    case failed(ModelDownloadFailure)
    /// The other Segue flavour holds the download lock (R67: one download at a time).
    case otherAppDownloading

    public var isInstalled: Bool {
        self == .installed
    }

    /// Downloading, verifying or waiting on the other flavour: Download is not offered.
    public var isBusy: Bool {
        switch self {
        case .downloading, .otherAppDownloading, .verifying: true
        default: false
        }
    }
}

/// The store as the pane sees it at one moment.
public struct LocalModelSnapshot: Sendable, Hashable {
    /// Curated entries first, in catalog order, then custom ones (Personal only).
    public var models: [LocalModelManifest]
    public var states: [String: LocalModelState]
    /// The model the MLX provider uses, if any is installed.
    public var activeModelID: String?
    /// Free space on the store's volume ("important usage" capacity), nil when unknown.
    public var freeDiskBytes: Int64?

    public init(
        models: [LocalModelManifest],
        states: [String: LocalModelState],
        activeModelID: String?,
        freeDiskBytes: Int64?,
    ) {
        self.models = models
        self.states = states
        self.activeModelID = activeModelID
        self.freeDiskBytes = freeDiskBytes
    }

    public func state(of id: String) -> LocalModelState {
        states[id] ?? .notInstalled
    }

    public static let empty = Self(models: [], states: [:], activeModelID: nil, freeDiskBytes: nil)
}

/// Why a store action was refused.
public enum LocalModelStoreError: String, Error, Sendable, Hashable, Codable {
    /// The id names no model in the catalog.
    case unknownModel
    /// The model is downloading; cancel first.
    case busy
    /// The store folder could not be changed.
    case fileSystem
    /// The app-group container is not reachable (a build without the entitlement).
    case unavailable
}

/// The model store behind Settings > AI (R66, R67, R99): downloads only when asked, verifies
/// every file, removes directly after the pane's confirmation. Implemented by `ModelStore`.
public protocol LocalModelInstaller: Sendable {
    /// The current snapshot (re-reads the disk).
    func snapshot() async -> LocalModelSnapshot
    /// Every change from now on, starting with the current snapshot.
    func updates() async -> AsyncStream<LocalModelSnapshot>
    /// Starts or resumes a download (never automatic: only from a click, R66).
    func download(_ id: String) async
    /// Stops a download and keeps its partial data.
    func cancelDownload(_ id: String) async
    /// Removes the model's files and any partial data directly, not via the Trash (R99).
    func delete(_ id: String) async throws(LocalModelStoreError)
    /// Makes `id` the model the MLX provider uses (one active MLX model, R62).
    func activate(_ id: String) async throws(LocalModelStoreError)
}
