import Foundation
import ModelPort
import ModelStore

/// Settings > AI > Advanced (Personal only, R62, R97): reads an `mlx-community` model's card
/// from the Hub and turns it into a pinned, verifiable manifest. Nothing downloads here; the
/// model's files download only when the user clicks Download on its card. The license shown
/// is the upstream one (the `base_model` card), not only the conversion's.
struct AdvancedModelsHub: Sendable {
    /// What the lookup found, before the user adds it.
    struct Card: Sendable, Hashable {
        var manifest: LocalModelManifest
        /// The conversion's own license id, when it differs from the upstream one.
        var conversionLicense: String?
    }

    enum LookupError: Error, Hashable {
        /// Only `mlx-community/<name>` repos are offered.
        case notMLXCommunity
        case notFound
        /// Gated models need an account; Segue never signs in.
        case gated
        /// The repo lacks a file the loader needs, or the Hub gave no digest for one.
        case unsupported(String)
        case network
    }

    var baseURL: URL = ModelStore.huggingFace
    var appVersion: String

    /// Looks up `repo` at its current `main` revision and pins that revision.
    func lookUp(_ repo: String) async throws(LookupError) -> Card {
        let repo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = repo.split(separator: "/")
        guard parts.count == 2, parts[0] == "mlx-community" else { throw .notMLXCommunity }
        let info = try await fetch(path: "/api/models/\(repo)/revision/main", query: "blobs=true")
        guard info.gated == nil || info.gated == .bool(false) else { throw .gated }
        guard let revision = info.sha else { throw .notFound }
        let files = try Self.files(from: info.siblings ?? [])
        let base = info.cardData?.baseModel
        var upstream = info.cardData
        if let base, let upstreamInfo = try? await fetch(path: "/api/models/\(base)", query: nil) {
            upstream = upstreamInfo.cardData ?? upstream
        }
        let licenseID = upstream?.license ?? info.cardData?.license ?? "unknown"
        let upstreamRepo = base ?? repo
        let licenseURL = upstream?.licenseLink.flatMap(URL.init(string:))
            ?? baseURL.appending(path: upstreamRepo)
        let weights = files.filter { $0.name.hasSuffix(".safetensors") }.reduce(0) { $0 + $1.size }
        let manifest = LocalModelManifest(
            id: "custom-" + repo.lowercased().replacingOccurrences(of: "/", with: "-"),
            displayName: String(parts[1]),
            status: .custom,
            role: .custom,
            repo: repo,
            revision: revision,
            files: files,
            license: .init(
                id: licenseID,
                name: upstream?.licenseName ?? licenseID,
                url: licenseURL,
                upstreamRepo: upstreamRepo,
            ),
            // The weights plus about a third for the cache and activations (the curated
            // 2.26 GB model peaked at 3.0 GB).
            memoryBytes: weights + weights / 3,
        )
        let conversion = info.cardData?.license
        return Card(
            manifest: manifest,
            conversionLicense: conversion != licenseID ? conversion : nil,
        )
    }

    /// The files the loader opens (config, generation config, weights and their index, the
    /// tokenizer and chat template), each with the Hub's digest: SHA256 for LFS files, the git
    /// blob id otherwise.
    static func files(from siblings: [HubModelInfo.Sibling]) throws(LookupError)
        -> [LocalModelManifest.File]
    {
        let wanted: (String) -> Bool = { name in
            [
                "config.json",
                "generation_config.json",
                "model.safetensors.index.json",
                "tokenizer.json",
                "tokenizer_config.json",
                "chat_template.jinja",
            ].contains(name)
                || (name.hasSuffix(".safetensors") && !name.contains("/"))
        }
        let files = siblings.filter { wanted($0.rfilename) }.map { sibling in
            LocalModelManifest.File(
                name: sibling.rfilename,
                size: sibling.lfs?.size ?? sibling.size ?? -1,
                sha256: sibling.lfs?.sha256,
                gitBlobID: sibling.lfs == nil ? sibling.blobId : nil,
            )
        }
        for required in ["config.json", "tokenizer.json", "tokenizer_config.json"]
            where !files.contains(where: { $0.name == required })
        {
            throw .unsupported(required)
        }
        guard files.contains(where: { $0.name.hasSuffix(".safetensors") }) else {
            throw .unsupported("safetensors weights")
        }
        guard files.allSatisfy({ $0.size >= 0 && ($0.sha256 != nil || $0.gitBlobID != nil) })
        else { throw .unsupported("file digests") }
        return files.sorted { $0.name < $1.name }
    }

    private func fetch(path: String, query: String?) async throws(LookupError) -> HubModelInfo {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.query = query
        guard let url = components?.url else { throw .notFound }
        var request = URLRequest(url: url)
        for (name, value) in ModelStore.hubHeaders(appVersion: appVersion) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let session = URLSession(configuration: ModelStore.hubSessionConfiguration())
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw .gated
        case 404: throw .notFound
        default: throw .network
        }
        do {
            return try JSONDecoder().decode(HubModelInfo.self, from: data)
        } catch {
            throw .notFound
        }
    }
}

/// The parts of the Hub's `/api/models/<repo>` answer the lookup reads.
struct HubModelInfo: Decodable, Sendable {
    struct Sibling: Decodable, Sendable {
        struct LFS: Decodable, Sendable {
            var sha256: String?
            var size: Int64?
        }

        var rfilename: String
        var size: Int64?
        var blobId: String?
        var lfs: LFS?
    }

    struct CardData: Decodable, Sendable {
        var license: String?
        var licenseName: String?
        var licenseLink: String?
        var baseModel: String?

        enum CodingKeys: String, CodingKey {
            case license
            case licenseName = "license_name"
            case licenseLink = "license_link"
            case baseModel = "base_model"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            license = try? container.decode(String.self, forKey: .license)
            licenseName = try? container.decode(String.self, forKey: .licenseName)
            licenseLink = try? container.decode(String.self, forKey: .licenseLink)
            // `base_model` is a string or a list (the first is the model it was made from).
            baseModel = (try? container.decode(String.self, forKey: .baseModel))
                ?? (try? container.decode([String].self, forKey: .baseModel))?.first
        }
    }

    /// `false`, or a gating mode string (`"auto"`, `"manual"`).
    enum Gated: Decodable, Sendable, Equatable {
        case bool(Bool)
        case mode(String)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .bool(flag)
            } else {
                self = try .mode(container.decode(String.self))
            }
        }
    }

    var sha: String?
    var gated: Gated?
    var siblings: [Sibling]?
    var cardData: CardData?
}
