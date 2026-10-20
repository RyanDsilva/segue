import AIEval
import ModelPort
import ModelStore
import SegueUI
import SwiftUI

/// Settings > AI > Advanced, Personal build only (R62, R97): look up an `mlx-community`
/// model, see its size and upstream license, add it (it then gets its own card above, where
/// Download is a click), choose the one active MLX model, run "Check this model" and remove it.
public enum AdvancedModels {
    /// The section's content, for `AIServices.advancedSection`.
    @MainActor
    public static func section(
        store: ModelStore,
        models: LocalModelsModel,
        appVersion: String,
        open: @escaping @MainActor (URL) -> Void,
    ) -> AnyView {
        AnyView(AdvancedModelsView(
            store: store,
            models: models,
            hub: AdvancedModelsHub(appVersion: appVersion),
            open: open,
        ))
    }
}

struct AdvancedModelsView: View {
    let store: ModelStore
    let models: LocalModelsModel
    let hub: AdvancedModelsHub
    let open: @MainActor (URL) -> Void

    @State private var repo = ""
    @State private var lookingUp = false
    @State private var card: AdvancedModelsHub.Card?
    @State private var message: String?
    @State private var checking: [String: String] = [:]
    @State private var results: [String: AdvancedModelsCheck.Outcome] = [:]
    @State private var removing: LocalModelManifest?

    private var snapshot: LocalModelSnapshot {
        models.snapshot
    }

    private var installed: [LocalModelManifest] {
        snapshot.models.filter { snapshot.state(of: $0.id).isInstalled }
    }

    var body: some View {
        Group {
            HStack {
                TextField("Model", text: $repo, prompt: Text("mlx-community/…"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(lookUp)
                    .accessibilityIdentifier("segue.settings.ai.advanced.repo")
                Button("Look Up", action: lookUp)
                    .disabled(repo.isEmpty || lookingUp)
                    .accessibilityIdentifier("segue.settings.ai.advanced.lookUp")
            }
            if lookingUp {
                ProgressView().controlSize(.small)
            }
            if let card {
                found(card)
            }
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if installed.count > 1 {
                Picker("Model used for AI", selection: Binding(
                    get: { snapshot.activeModelID ?? "" },
                    set: { id in Task { try? await store.activate(id) } },
                )) {
                    ForEach(installed) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .accessibilityIdentifier("segue.settings.ai.advanced.active")
            }
            ForEach(snapshot.models.filter { $0.role == .custom }) { model in
                customRow(model)
            }
            Text("Custom models run only in this Personal build. Segue checks every file "
                + "against the Hub's digests, and the model works only on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(
            removing.map { "Remove \($0.displayName)?" } ?? "",
            isPresented: Binding(
                get: { removing != nil },
                set: {
                    if !$0 {
                        removing = nil
                    }
                },
            ),
            titleVisibility: .visible,
            presenting: removing,
        ) { model in
            Button("Remove", role: .destructive) {
                Task {
                    try? await store.removeCustomModel(model.id)
                    await models.refresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This deletes its files from this Mac at once and removes it from the list.")
        }
    }

    private func found(_ card: AdvancedModelsHub.Card) -> some View {
        let model = card.manifest
        return VStack(alignment: .leading, spacing: 6) {
            Text(model.displayName).font(.headline)
            Text("Download \(size(model.downloadBytes)), about \(size(model.memoryBytes)) of "
                + "memory while it works")
                .font(.callout)
            HStack(spacing: 4) {
                Text("License (\(model.license.upstreamRepo)):").font(.callout)
                Button(model.license.name) { open(model.license.url) }
                    .buttonStyle(.link)
            }
            if let conversion = card.conversionLicense {
                Text("The mlx-community conversion says \(conversion).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Add Model") { add(model) }
                .accessibilityIdentifier("segue.settings.ai.advanced.add")
        }
    }

    private func customRow(_ model: LocalModelManifest) -> some View {
        let state = snapshot.state(of: model.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.displayName)
                Spacer()
                if state.isInstalled {
                    if let progress = checking[model.id] {
                        Text(progress).font(.callout).monospacedDigit()
                    } else {
                        Button("Check This Model") { check(model) }
                    }
                }
                Button("Remove…") { removing = model }
            }
            if let outcome = results[model.id] {
                Text(summary(outcome))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func lookUp() {
        let repo = repo
        lookingUp = true
        card = nil
        message = nil
        Task {
            do throws(AdvancedModelsHub.LookupError) {
                card = try await hub.lookUp(repo)
            } catch {
                message = Self.text(error)
            }
            lookingUp = false
        }
    }

    private func add(_ model: LocalModelManifest) {
        Task {
            do throws(LocalModelStoreError) {
                try await store.addCustomModel(model)
                card = nil
                repo = ""
                message = "Added. Download it from its card above."
            } catch {
                message = "Segue could not add this model."
            }
            await models.refresh()
        }
    }

    private func check(_ model: LocalModelManifest) {
        checking[model.id] = "Starting…"
        Task {
            guard let folder = await store.folder(for: model.id) else {
                checking[model.id] = nil
                return
            }
            let outcome = await AdvancedModelsCheck
                .run(model: model, folder: folder) { done, total in
                    Task { @MainActor in checking[model.id] = "\(done) of \(total)" }
                }
            checking[model.id] = nil
            if let outcome {
                results[model.id] = outcome
            } else {
                message = "The check fixtures are missing from this build."
            }
        }
    }

    // MARK: - Text

    private func summary(_ outcome: AdvancedModelsCheck.Outcome) -> String {
        func percent(_ value: Double) -> String {
            String(format: "%.0f%%", value * 100)
        }
        var text = "Labels \(percent(outcome.score.labelAccuracy)), title and artist "
            + "\(percent(outcome.score.titleArtistAccuracy))"
        if let curated = outcome.curated {
            text += " (curated model: \(percent(curated.labelAccuracy)), "
                + "\(percent(curated.titleArtistAccuracy)))"
        }
        return text + "."
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func text(_ error: AdvancedModelsHub.LookupError) -> String {
        switch error {
        case .notMLXCommunity: "Enter an mlx-community model, like mlx-community/Qwen3-4B-4bit."
        case .notFound: "No such model on Hugging Face."
        case .gated: "This model needs a Hugging Face account. Segue cannot download it."
        case let .unsupported(what): "Segue cannot run this model (no \(what))."
        case .network: "Hugging Face could not be reached."
        }
    }
}
