import Foundation
import ModelPort

/// Model residency (R94): the model is loaded for a paste or a set request and unloaded right
/// after. A paste is two or three back-to-back calls (labels, metadata, unknown lines), so the
/// unload waits a short `linger` after the last call: a call that follows at once reuses the
/// loaded model, and nothing stays resident between pastes. One call at a time: a second
/// call while one runs gets `busy` (the router retries once, then falls through to FM).
actor ModelResidency {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let engine: any GuidedEngine
    private let linger: Duration
    private let sleep: Sleep
    private var loaded: (folder: URL, model: any LoadedGuidedModel)?
    private var inUse = false
    private var unloadTask: Task<Void, Never>?
    /// Loads so far (tests read it).
    private(set) var loadCount = 0

    init(engine: any GuidedEngine, linger: Duration, sleep: @escaping Sleep) {
        self.engine = engine
        self.linger = linger
        self.sleep = sleep
    }

    var isLoaded: Bool {
        loaded != nil
    }

    /// The model for `folder`, loading it (and unloading any other) when needed.
    func acquire(folder: URL) async throws(ProviderError) -> any LoadedGuidedModel {
        guard !inUse else { throw .busy }
        inUse = true
        unloadTask?.cancel()
        unloadTask = nil
        if let loaded, loaded.folder == folder {
            return loaded.model
        }
        if let previous = loaded {
            loaded = nil
            await previous.model.unload()
        }
        do throws(GuidedFailure) {
            let model = try await engine.load(folder: folder)
            loadCount += 1
            loaded = (folder, model)
            return model
        } catch {
            inUse = false
            throw .other
        }
    }

    /// The call is over: the model unloads after `linger` unless another call takes it.
    func release() {
        inUse = false
        unloadTask?.cancel()
        let linger = linger
        let sleep = sleep
        unloadTask = Task { [weak self] in
            do {
                try await sleep(linger)
            } catch {
                return
            }
            await self?.unloadIfIdle()
        }
    }

    /// Unloads now unless a call is running (a show starting, the app going away).
    func unloadIfIdle() async {
        guard !inUse, let current = loaded else { return }
        loaded = nil
        unloadTask = nil
        await current.model.unload()
    }
}
