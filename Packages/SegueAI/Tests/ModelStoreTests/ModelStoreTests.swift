import CryptoKit
import Foundation
import ModelPort
@testable import ModelStore
import Testing

/// The downloader and store against a real local HTTP server (spec 14: resume, cancel,
/// checksum mismatch, disk full, redirect, header assertions), plus the store path, backup
/// exclusion, the cross-flavour lock and direct delete (R99).
@Suite(.serialized)
struct ModelStoreTests {
    typealias Fixture = ModelStoreFixture

    /// Waits until the store reports a state for the model that `done` accepts.
    static func wait(
        for store: ModelStore,
        timeout: Duration = .seconds(20),
        until done: (LocalModelState) -> Bool,
    ) async throws -> LocalModelState {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            let state = await store.snapshot().state(of: "test-model")
            if done(state) {
                return state
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("timed out waiting for the model state")
        return await store.snapshot().state(of: "test-model")
    }

    @Test
    func `a download follows the CDN redirect with Segue's headers on every hop and verifies`()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let server = try LocalHTTPServer { request in
            // The Hub answers /resolve/ with a redirect to its CDN, as huggingface.co does.
            if request.path.contains("/resolve/") {
                let file = request.path.split(separator: "/").last ?? ""
                return .redirect(to: "/cdn/\(file)")
            }
            guard let body = fixture.body(for: request.path) else { return .status(404) }
            return .file(body, for: request)
        }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base)

        #expect(await store.snapshot().state(of: "test-model") == .notInstalled)
        #expect(server.captured.isEmpty, "nothing downloads without a click")
        await store.download("test-model")
        let state = try await Self.wait(for: store) { !$0.isBusy }

        #expect(state == .installed)
        let requests = server.captured
        #expect(requests.map(\.path) == [
            "/mlx-community/Test-Model-4bit/resolve/\(fixture.manifest.revision)/config.json",
            "/cdn/config.json",
            "/mlx-community/Test-Model-4bit/resolve/\(fixture.manifest.revision)/model.safetensors",
            "/cdn/model.safetensors",
        ])
        for request in requests {
            // R54: a fixed User-Agent and no language list, on the CDN hop too.
            #expect(request.headers["user-agent"] == "Segue/0.5")
            #expect(request.headers["accept-language"] == nil
                || request.headers["accept-language"] == "*")
            #expect(request.headers["cookie"] == nil)
            let allowed: Set = [
                "host", "user-agent", "accept-language", "accept", "accept-encoding", "connection",
                "range", "priority",
            ]
            #expect(Set(request.headers.keys).isSubset(of: allowed), "\(request.headers.keys)")
        }
        let weights = try Data(contentsOf: fixture.modelFolder.appending(path: "model.safetensors"))
        #expect(weights == fixture.weights)
        #expect(await store.activeModel()?.folder == fixture.modelFolder)
    }

    @Test
    func `the store sits at root, repo, revision and is excluded from backup`() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let server = try LocalHTTPServer { request in
            fixture.body(for: request.path).map { .file($0, for: request) } ?? .status(404)
        }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base)
        await store.download("test-model")
        _ = try await Self.wait(for: store) { !$0.isBusy }

        #expect(fixture.modelFolder.path.hasSuffix(
            "/Models/mlx-community/Test-Model-4bit/\(fixture.manifest.revision)/",
        ) || fixture.modelFolder.path.hasSuffix(
            "/Models/mlx-community/Test-Model-4bit/\(fixture.manifest.revision)",
        ))
        let values = try fixture.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        // The partial folder is gone once the model is complete.
        #expect(!FileManager.default.fileExists(
            atPath: fixture.location.partialDirectory(for: fixture.manifest).path,
        ))
        #expect(ModelStoreLocation.appGroupID == "V6BM673U35.dev.ryandsilva.segue.models")
    }

    @Test
    func `a partial file resumes with a Range request`() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let partialFolder = fixture.location.partialDirectory(for: fixture.manifest)
        try FileManager.default.createDirectory(
            at: partialFolder,
            withIntermediateDirectories: true,
        )
        try fixture.weights.prefix(250_000).write(
            to: partialFolder.appending(path: "model.safetensors"),
        )
        let server = try LocalHTTPServer { request in
            fixture.body(for: request.path).map { .file($0, for: request) } ?? .status(404)
        }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base)
        #expect(await store.snapshot().state(of: "test-model")
            == .paused(received: 250_000, total: fixture.manifest.downloadBytes))

        await store.download("test-model")
        #expect(try await Self.wait(for: store) { !$0.isBusy } == .installed)
        let weightsRequest = try #require(server.captured.last)
        #expect(weightsRequest.headers["range"] == "bytes=250000-")
    }

    @Test
    func `cancel keeps the partial data and Download resumes it`() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let server = try LocalHTTPServer { request in
            guard let body = fixture.body(for: request.path) else { return .status(404) }
            return .file(body, for: request, chunkSize: 16 << 10, chunkDelay: .milliseconds(40))
        }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base)
        await store.download("test-model")
        _ = try await Self.wait(for: store) { state in
            if case let .downloading(received, _) = state {
                return received > 100_000
            }
            return false
        }
        await store.cancelDownload("test-model")
        let paused = try await Self.wait(for: store) { !$0.isBusy }
        guard case let .paused(received, total) = paused else {
            Issue.record("expected paused, got \(paused)")
            return
        }
        #expect(received > 0 && received < total)

        await store.download("test-model")
        #expect(try await Self.wait(for: store) { !$0.isBusy } == .installed)
        #expect(server.captured.last?.headers["range"] != nil)
        let weights = try Data(contentsOf: fixture.modelFolder.appending(path: "model.safetensors"))
        #expect(weights == fixture.weights)
    }

    @Test
    func `a checksum mismatch deletes the file and fails the download`() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let server = try LocalHTTPServer { request in
            guard var body = fixture.body(for: request.path) else { return .status(404) }
            if request.path.hasSuffix("model.safetensors") {
                body[1000] ^= 0xFF
            }
            return .file(body, for: request)
        }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base)
        await store.download("test-model")

        #expect(try await Self.wait(for: store) { !$0.isBusy } == .failed(.checksum))
        let fileManager = FileManager.default
        #expect(!fileManager.fileExists(
            atPath: fixture.modelFolder.appending(path: "model.safetensors").path,
        ))
        #expect(!fileManager.fileExists(atPath: fixture.location.partialDirectory(
            for: fixture.manifest,
        ).appending(path: "model.safetensors").path))
        #expect(await store.activeModel() == nil)
    }

    @Test
    func `too little free space fails before any request`() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let server = try LocalHTTPServer { _ in .status(500) }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base) { _ in 10000 }
        await store.download("test-model")

        #expect(await store.snapshot().state(of: "test-model") == .failed(.disk))
        #expect(server.captured.isEmpty)
    }

    @Test
    func `a server error is a network failure`() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let server = try LocalHTTPServer { _ in .status(503) }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base)
        await store.download("test-model")
        #expect(try await Self.wait(for: store) { !$0.isBusy } == .failed(.network))
    }

    @Test
    func `files already in place are verified and adopted without a request`() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(
            at: fixture.modelFolder,
            withIntermediateDirectories: true,
        )
        try fixture.config.write(to: fixture.modelFolder.appending(path: "config.json"))
        try fixture.weights.write(to: fixture.modelFolder.appending(path: "model.safetensors"))
        let server = try LocalHTTPServer { _ in .status(500) }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base)
        // No marker yet: not installed until verified.
        #expect(await store.snapshot().state(of: "test-model") != .installed)

        await store.download("test-model")
        #expect(try await Self.wait(for: store) { !$0.isBusy } == .installed)
        #expect(server.captured.isEmpty)
    }

    @Test
    func `the other flavour's download lock blocks a second download`() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.location.prepare()
        // The other flavour holds the lock (another open file description, as another
        // process would).
        let held = try #require(DownloadLock.acquire(
            at: fixture.location.lockURL,
            modelID: "test-model",
        ))
        let server = try LocalHTTPServer { _ in .status(500) }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base)
        #expect(await store.snapshot().state(of: "test-model") == .otherAppDownloading)
        await store.download("test-model")
        #expect(await store.snapshot().state(of: "test-model") == .otherAppDownloading)
        #expect(server.captured.isEmpty)
        withExtendedLifetime(held) {}
    }

    @Test
    func `delete removes the model directly, not via the Trash`() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let server = try LocalHTTPServer { request in
            fixture.body(for: request.path).map { .file($0, for: request) } ?? .status(404)
        }
        let base = try await server.start()
        defer { server.stop() }
        let store = fixture.store(baseURL: base)
        await store.download("test-model")
        #expect(try await Self.wait(for: store) { !$0.isBusy } == .installed)

        try await store.delete("test-model")

        #expect(await store.snapshot().state(of: "test-model") == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: fixture.modelFolder.path))
        // Empty repo folders go too; the store root stays.
        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appending(path: "mlx-community").path,
        ))
        #expect(FileManager.default.fileExists(atPath: fixture.root.path))
    }

    @Test
    func `custom manifests may not climb out of the store`() {
        let fixture = try? Fixture()
        guard var manifest = fixture?.manifest else { return }
        #expect(ModelStoreLocation.isSafe(manifest))
        manifest.repo = "../escape"
        #expect(!ModelStoreLocation.isSafe(manifest))
        manifest.repo = "mlx-community/x"
        manifest.files[0].name = "../../config.json"
        #expect(!ModelStoreLocation.isSafe(manifest))
        manifest.files[0].name = "config.json"
        manifest.revision = "main"
        #expect(!ModelStoreLocation.isSafe(manifest))
    }
}

/// A two-file model: a small config and a 600 KB "weights" file.
struct ModelStoreFixture {
    let config = Data(#"{"model_type":"qwen3"}"#.utf8)
    let weights = Data((0 ..< 600_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(
                path: "segue-model-store-\(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
            .appending(path: "Models", directoryHint: .isDirectory)
    }

    var manifest: LocalModelManifest {
        LocalModelManifest(
            id: "test-model",
            displayName: "Test Model",
            status: .locked,
            role: .standard,
            repo: "mlx-community/Test-Model-4bit",
            revision: String(repeating: "ab", count: 20),
            files: [
                .init(name: "config.json", size: Int64(config.count), sha256: Self.sha(config)),
                .init(
                    name: "model.safetensors",
                    size: Int64(weights.count),
                    sha256: Self.sha(weights),
                ),
            ],
            license: .init(
                id: "apache-2.0",
                name: "Apache-2.0",
                url: URL(string: "https://example.com/LICENSE")!,
                upstreamRepo: "Test/Test-Model",
            ),
            memoryBytes: 3_000_000_000,
        )
    }

    var location: ModelStoreLocation {
        ModelStoreLocation(root: root)
    }

    var modelFolder: URL {
        location.modelDirectory(for: manifest)
    }

    func body(for path: String) -> Data? {
        if path.hasSuffix("/config.json") {
            return config
        }
        if path.hasSuffix("/model.safetensors") {
            return weights
        }
        return nil
    }

    func store(
        baseURL: URL,
        freeSpace: @escaping @Sendable (URL) -> Int64? = { _ in 1 << 40 },
    ) -> ModelStore {
        ModelStore(
            location: location,
            curated: [manifest],
            options: .init(baseURL: baseURL, appVersion: "0.5", freeSpace: freeSpace),
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
