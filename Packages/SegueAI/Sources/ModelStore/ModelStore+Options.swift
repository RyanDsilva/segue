import Foundation
import ModelPort

public extension ModelStore {
    /// The "active model" preference (one active MLX model, R62), stored by the app.
    struct ActiveModelPreference: Sendable {
        public var read: @Sendable () -> String?
        public var write: @Sendable (String?) -> Void

        public init(
            read: @escaping @Sendable () -> String?,
            write: @escaping @Sendable (String?) -> Void,
        ) {
            self.read = read
            self.write = write
        }

        /// Kept in memory only (tests, command-line tools).
        public static func inMemory(_ initial: String? = nil) -> Self {
            let box = Box(initial)
            return Self(read: { box.value }, write: { box.value = $0 })
        }

        /// A UserDefaults key (each flavour keeps its own choice).
        public static func userDefaults(
            key: String = "ai.activeModelID",
            suiteName: String? = nil,
        ) -> Self {
            Self(
                read: { UserDefaults(suiteName: suiteName)?.string(forKey: key) },
                write: { value in
                    let defaults = UserDefaults(suiteName: suiteName)
                    if let value {
                        defaults?.set(value, forKey: key)
                    } else {
                        defaults?.removeObject(forKey: key)
                    }
                },
            )
        }

        private final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: String?

            init(_ value: String?) {
                stored = value
            }

            var value: String? {
                get { lock.withLock { stored } }
                set { lock.withLock { stored = newValue } }
            }
        }
    }

    struct Options: Sendable {
        /// The Hub (tests point it at a local server).
        public var baseURL: URL
        /// `Segue/<version>` in the User-Agent.
        public var appVersion: String
        /// Advanced custom models (Personal only, R62).
        public var allowsCustomModels: Bool
        /// Free space kept beyond the download itself.
        public var spaceMargin: Int64
        /// Free bytes on the volume of a folder (injectable for the disk-full test).
        public var freeSpace: @Sendable (URL) -> Int64?
        public var activeModel: ActiveModelPreference

        public init(
            baseURL: URL = ModelStore.huggingFace,
            appVersion: String,
            allowsCustomModels: Bool = false,
            spaceMargin: Int64 = 256 << 20,
            freeSpace: @escaping @Sendable (URL) -> Int64? = ModelStore.volumeFreeSpace,
            activeModel: ActiveModelPreference = .inMemory(),
        ) {
            self.baseURL = baseURL
            self.appVersion = appVersion
            self.allowsCustomModels = allowsCustomModels
            self.spaceMargin = spaceMargin
            self.freeSpace = freeSpace
            self.activeModel = activeModel
        }
    }

    static let huggingFace = URL(string: "https://huggingface.co")!

    /// The curated catalog bundled with the app (empty if the resource is unreadable, which a
    /// unit test catches).
    static let curatedCatalog: [LocalModelManifest] = {
        guard let url = Bundle.module.url(forResource: "curated-models", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? LocalModelCatalog.decode(data)
        else { return [] }
        return catalog.models
    }()

    /// The volume's "important usage" free capacity (privacy manifest reason E174.1).
    static let volumeFreeSpace: @Sendable (URL) -> Int64? = { url in
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

public extension ModelStore {
    /// R54 headers for any Hub request (downloads, and Personal's model card lookups).
    static func hubHeaders(appVersion: String) -> [String: String] {
        FileTransfer.headers(appVersion: appVersion)
    }

    /// The ephemeral, cookie-free session configuration every Hub request uses.
    static func hubSessionConfiguration() -> URLSessionConfiguration {
        FileTransfer.configuration()
    }
}
