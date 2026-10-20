#if os(macOS)
    import Foundation
    import ModelPort
    import Observation
    import Services

    /// The Settings > AI model card's state (R64, R66, R68, R99): the store's snapshot, kept
    /// current while the pane is open, and the click-only actions. The store itself
    /// (`ModelStore`, in SegueAI) is behind the `LocalModelInstaller` port, so SegueUI never
    /// links MLX and tests drive the pane with `ScriptedModelInstaller`.
    @MainActor
    @Observable
    public final class LocalModelsModel {
        /// Macs with less memory than this get the low-RAM note (R68; never blocks).
        public static let lowMemoryThreshold: UInt64 = 16 << 30

        public private(set) var snapshot: LocalModelSnapshot = .empty
        /// The last delete that failed, shown under the card.
        public private(set) var deleteError: LocalModelStoreError?
        @ObservationIgnored public let installer: (any LocalModelInstaller)?
        /// The Mac's memory (injectable for the low-RAM tests).
        @ObservationIgnored public let physicalMemory: UInt64
        @ObservationIgnored private var watcher: Task<Void, Never>?
        /// `Segue.AI.modelDownload` (R74): called once per download the user started, when it
        /// ends (completed, cancelled or failed).
        @ObservationIgnored public var onDownloadFinished: (@MainActor (ModelDownloadSummary)
            -> Void)?
        /// Downloads the user started: when, and whether the store reported them busy yet.
        @ObservationIgnored private var started: [String: (date: Date, seenBusy: Bool)] = [:]

        /// - Parameter installer: nil when this build has no model store (previews, tests
        ///   that do not need one).
        public init(
            installer: (any LocalModelInstaller)?,
            physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
        ) {
            self.installer = installer
            self.physicalMemory = physicalMemory
        }

        /// Whether the low-RAM note shows.
        public var isLowMemory: Bool {
            physicalMemory < Self.lowMemoryThreshold
        }

        /// R120: whether the quiet download links (the Welcome card, the review sheet footer)
        /// offer the curated model. Never on Macs under 16 GB, where Apple Intelligence is the
        /// default and the download stays an opt-in in Settings > AI; never once the model is
        /// installed or on its way.
        public var suggestsDownload: Bool {
            guard !isLowMemory else { return false }
            guard let curated = snapshot.models.first(where: { $0.role == .standard }) else {
                return installer != nil
            }
            let state = snapshot.state(of: curated.id)
            return !state.isInstalled && !state.isBusy
        }

        /// Starts following the store (the pane calls it when it appears; idempotent).
        public func start() {
            guard watcher == nil, let installer else { return }
            watcher = Task { [weak self] in
                for await snapshot in await installer.updates() {
                    self?.apply(snapshot)
                }
            }
        }

        /// Stops following the store (the pane disappeared); a download in progress keeps it
        /// following until the download ends, so its result is still recorded.
        public func stop() {
            guard started.isEmpty else { return }
            watcher?.cancel()
            watcher = nil
        }

        /// Re-reads the store once (tests, and the pane before its stream delivers).
        public func refresh() async {
            guard let installer else { return }
            await apply(installer.snapshot())
        }

        public func download(_ id: String) {
            deleteError = nil
            guard let installer else { return }
            started[id] = (Date(), false)
            start()
            Task {
                await installer.download(id)
                await refresh()
            }
        }

        public func cancel(_ id: String) {
            guard let installer else { return }
            Task {
                await installer.cancelDownload(id)
                await refresh()
            }
        }

        /// Takes a snapshot and reports the downloads it shows ended.
        private func apply(_ snapshot: LocalModelSnapshot) {
            self.snapshot = snapshot
            for (id, entry) in started {
                let state = snapshot.state(of: id)
                if state.isBusy {
                    started[id]?.seenBusy = true
                    continue
                }
                let result: ModelDownloadResult? = switch state {
                case .installed: .completed
                case let .failed(failure): ModelDownloadResult(rawValue: failure.rawValue) ?? .other
                case .notInstalled, .paused: entry.seenBusy ? .cancelled : nil
                default: nil
                }
                guard let result else { continue }
                started[id] = nil
                let custom = snapshot.models.first { $0.id == id }?.role == .custom
                onDownloadFinished?(ModelDownloadSummary(
                    result: result,
                    kind: custom ? .custom : .curated,
                    duration: DownloadDurationBucket(seconds: Date().timeIntervalSince(entry.date)),
                    ramUnder16: isLowMemory,
                ))
            }
        }

        /// Removes the model directly (R99), after the pane's confirmation.
        public func delete(_ id: String) async {
            guard let installer else { return }
            do throws(LocalModelStoreError) {
                try await installer.delete(id)
                deleteError = nil
            } catch {
                deleteError = error
            }
            await refresh()
        }
    }

    /// A model store that downloads nothing: it walks a click through scripted progress to
    /// installed. In-process tests and Debug test launches (E2E) use it, so no test ever
    /// touches the network or the real app-group store.
    public actor ScriptedModelInstaller: LocalModelInstaller {
        private var snapshotValue: LocalModelSnapshot
        private var observers: [UUID: AsyncStream<LocalModelSnapshot>.Continuation] = [:]
        private let step: Duration
        /// Every action, in order (`download:<id>`, `cancel:<id>`, `delete:<id>`).
        public private(set) var actions: [String] = []

        /// - Parameters:
        ///   - step: the delay between scripted progress steps.
        public init(
            models: [LocalModelManifest],
            states: [String: LocalModelState] = [:],
            freeDiskBytes: Int64? = 120_000_000_000,
            step: Duration = .milliseconds(150),
        ) {
            snapshotValue = LocalModelSnapshot(
                models: models,
                states: states,
                activeModelID: states.first { $0.value == .installed }?.key,
                freeDiskBytes: freeDiskBytes,
            )
            self.step = step
        }

        public func snapshot() -> LocalModelSnapshot {
            snapshotValue
        }

        public func updates() -> AsyncStream<LocalModelSnapshot> {
            let (stream, continuation) = AsyncStream<LocalModelSnapshot>.makeStream(
                bufferingPolicy: .bufferingNewest(1),
            )
            let id = UUID()
            observers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.drop(id) }
            }
            continuation.yield(snapshotValue)
            return stream
        }

        public func download(_ id: String) {
            actions.append("download:\(id)")
            guard let model = snapshotValue.models.first(where: { $0.id == id }) else { return }
            let total = model.downloadBytes
            set(id, .downloading(received: 0, total: total))
            let step = step
            Task {
                for fraction in [0.25, 0.5, 0.75, 1.0] {
                    try? await Task.sleep(for: step)
                    guard isDownloading(id) else { return }
                    set(id, .downloading(received: Int64(Double(total) * fraction), total: total))
                }
                try? await Task.sleep(for: step)
                guard isDownloading(id) else { return }
                set(id, .installed)
            }
        }

        public func cancelDownload(_ id: String) {
            actions.append("cancel:\(id)")
            if case let .downloading(received, total) = snapshotValue.state(of: id) {
                set(id, .paused(received: received, total: total))
            }
        }

        public func delete(_ id: String) throws(LocalModelStoreError) {
            actions.append("delete:\(id)")
            guard snapshotValue.models.contains(where: { $0.id == id }) else {
                throw .unknownModel
            }
            guard !snapshotValue.state(of: id).isBusy else { throw .busy }
            set(id, .notInstalled)
        }

        public func activate(_ id: String) throws(LocalModelStoreError) {
            guard snapshotValue.models.contains(where: { $0.id == id }) else {
                throw .unknownModel
            }
            snapshotValue.activeModelID = id
            publish()
        }

        private func isDownloading(_ id: String) -> Bool {
            if case .downloading = snapshotValue.state(of: id) {
                return true
            }
            return false
        }

        private func set(_ id: String, _ state: LocalModelState) {
            snapshotValue.states[id] = state
            if state == .installed, snapshotValue.activeModelID == nil {
                snapshotValue.activeModelID = id
            } else if state != .installed, snapshotValue.activeModelID == id {
                snapshotValue.activeModelID = nil
            }
            publish()
        }

        private func publish() {
            for continuation in observers.values {
                continuation.yield(snapshotValue)
            }
        }

        private func drop(_ id: UUID) {
            observers[id] = nil
        }
    }
#endif
