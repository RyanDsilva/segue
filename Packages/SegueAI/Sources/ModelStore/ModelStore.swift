import Foundation
import ModelPort

/// The local model store (spec 5.2, 5.3; R66, R67, R99): the curated catalog plus, in the
/// Personal flavour, custom models (R62); downloads on request only, per-file digest checks,
/// the cross-flavour lock, and direct removal. State is read from disk on every snapshot, so
/// what the other flavour installed or removed shows up without coordination.
public actor ModelStore: LocalModelInstaller {
    struct Job {
        var task: Task<Void, Never>?
        var transfer: FileTransfer?
        let lock: DownloadLock
    }

    let location: ModelStoreLocation?
    private let curated: [LocalModelManifest]
    let options: Options
    private var custom: [LocalModelManifest] = []
    /// Transient states only (downloading, verifying, paused, failed); installed and not
    /// installed come from the disk.
    var transient: [String: LocalModelState] = [:]
    var jobs: [String: Job] = [:]
    private var observers: [UUID: AsyncStream<LocalModelSnapshot>.Continuation] = [:]

    public init(
        location: ModelStoreLocation?,
        curated: [LocalModelManifest] = ModelStore.curatedCatalog,
        options: Options,
    ) {
        self.location = location
        self.curated = curated
        self.options = options
        if options.allowsCustomModels, let location,
           let data = try? Data(contentsOf: location.customCatalogURL),
           let catalog = try? LocalModelCatalog.decode(data)
        {
            custom = catalog.models.filter { model in
                model.role == .custom && ModelStoreLocation.isSafe(model) && model.isVerifiable
            }
        }
    }

    // MARK: - LocalModelInstaller

    public func snapshot() -> LocalModelSnapshot {
        let models = curated + custom
        var states: [String: LocalModelState] = [:]
        for model in models {
            states[model.id] = state(of: model)
        }
        return LocalModelSnapshot(
            models: models,
            states: states,
            activeModelID: activeInstalled()?.id,
            freeDiskBytes: location.flatMap { options.freeSpace($0.root) },
        )
    }

    public func updates() -> AsyncStream<LocalModelSnapshot> {
        let (stream, continuation) = AsyncStream<LocalModelSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1),
        )
        let id = UUID()
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        continuation.yield(snapshot())
        return stream
    }

    public func download(_ id: String) {
        guard let model = model(id), jobs[id] == nil else { return }
        guard let location else {
            setTransient(id, .failed(.other))
            return
        }
        guard !isInstalled(model, in: location) else {
            transient[id] = nil
            publish()
            return
        }
        do {
            try location.prepare()
        } catch {
            setTransient(id, .failed(.other))
            return
        }
        guard let lock = DownloadLock.acquire(at: location.lockURL, modelID: id) else {
            setTransient(id, .otherAppDownloading)
            return
        }
        let needed = remainingBytes(model, in: location) + options.spaceMargin
        if let free = options.freeSpace(location.root), free < needed {
            setTransient(id, .failed(.disk))
            return
        }
        jobs[id] = Job(task: nil, transfer: nil, lock: lock)
        setTransient(id, .verifying)
        let options = options
        jobs[id]?.task = Task.detached(priority: .utility) { [weak self] in
            let report: @Sendable (Event) async -> Void = { [weak self] event in
                await self?.handle(event, for: id)
            }
            let outcome = await Self.run(
                model,
                location: location,
                options: options,
                report: report,
            )
            await self?.finish(id, outcome: outcome)
        }
    }

    public func cancelDownload(_ id: String) {
        guard let job = jobs[id] else { return }
        job.task?.cancel()
        job.transfer?.cancel()
    }

    public func delete(_ id: String) throws(LocalModelStoreError) {
        guard let model = model(id) else { throw .unknownModel }
        guard let location else { throw .unavailable }
        guard jobs[id] == nil, DownloadLock.holder(at: location.lockURL) != id else {
            throw .busy
        }
        let fileManager = FileManager.default
        do {
            for folder in [
                location.modelDirectory(for: model),
                location.partialDirectory(for: model),
            ]
                where fileManager.fileExists(atPath: folder.path)
            {
                // R99: removed directly, not via the Trash (re-downloadable app data).
                try fileManager.removeItem(at: folder)
                removeEmptyParents(of: folder, below: location.root)
            }
        } catch {
            throw .fileSystem
        }
        transient[id] = nil
        if options.activeModel.read() == id {
            options.activeModel.write(nil)
        }
        publish()
    }

    public func activate(_ id: String) throws(LocalModelStoreError) {
        guard model(id) != nil else { throw .unknownModel }
        options.activeModel.write(id)
        publish()
    }

    // MARK: - For the MLX provider

    /// The model the MLX provider runs and its folder: the chosen one when it is installed,
    /// else the first installed curated entry in catalog order.
    public func activeModel() -> (manifest: LocalModelManifest, folder: URL)? {
        guard let location, let model = activeInstalled() else { return nil }
        return (model, location.modelDirectory(for: model))
    }

    /// Where `id`'s files live (installed or not), or nil without a store.
    public func folder(for id: String) -> URL? {
        guard let location, let model = model(id) else { return nil }
        return location.modelDirectory(for: model)
    }

    // MARK: - Custom models (Personal, R62)

    /// Adds (or replaces) a custom model entry; downloading stays a separate click.
    public func addCustomModel(_ manifest: LocalModelManifest) throws(LocalModelStoreError) {
        guard options.allowsCustomModels, let location else { throw .unavailable }
        guard manifest.role == .custom, ModelStoreLocation.isSafe(manifest),
              manifest.isVerifiable, !curated.contains(where: { $0.id == manifest.id })
        else { throw .unknownModel }
        custom.removeAll { $0.id == manifest.id }
        custom.append(manifest)
        do {
            try location.prepare()
            let data = try JSONEncoder().encode(LocalModelCatalog(models: custom))
            try data.write(to: location.customCatalogURL, options: .atomic)
        } catch {
            throw .fileSystem
        }
        publish()
    }

    /// Deletes a custom model's files and forgets the entry.
    public func removeCustomModel(_ id: String) throws(LocalModelStoreError) {
        guard custom.contains(where: { $0.id == id }), let location else { throw .unknownModel }
        try delete(id)
        custom.removeAll { $0.id == id }
        do {
            let data = try JSONEncoder().encode(LocalModelCatalog(models: custom))
            try data.write(to: location.customCatalogURL, options: .atomic)
        } catch {
            throw .fileSystem
        }
        publish()
    }

    // MARK: - State

    private func model(_ id: String) -> LocalModelManifest? {
        (curated + custom).first { $0.id == id }
    }

    private func state(of model: LocalModelManifest) -> LocalModelState {
        if jobs[model.id] != nil, let state = transient[model.id] {
            return state
        }
        guard let location else { return .notInstalled }
        if isInstalled(model, in: location) {
            return .installed
        }
        if let holder = DownloadLock.holder(at: location.lockURL), jobs.isEmpty,
           holder == model.id
        {
            return .otherAppDownloading
        }
        if let state = transient[model.id], state != .otherAppDownloading {
            return state
        }
        let partial = partialBytes(model, in: location)
        return partial > 0 ? .paused(received: partial, total: model.downloadBytes) : .notInstalled
    }

    private func activeInstalled() -> LocalModelManifest? {
        guard let location else { return nil }
        if let chosen = options.activeModel.read(), let model = model(chosen),
           isInstalled(model, in: location)
        {
            return model
        }
        return curated.first { isInstalled($0, in: location) }
    }

    func setTransient(_ id: String, _ state: LocalModelState) {
        transient[id] = state
        publish()
    }

    func publish() {
        guard !observers.isEmpty else { return }
        let snapshot = snapshot()
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
