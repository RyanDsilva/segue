import AppKit
import Foundation
import ModelPort
@testable import SegueUI
import Services
import SwiftUI
import Testing

/// Settings > AI in process (P3-3): the toggle drives the router's gate (R93), the model card
/// through every store state with `ScriptedModelInstaller` (nothing downloads without a click,
/// R66; direct delete, R99), the low-memory note (R68), the R69 notes per Foundation Models
/// reason, and Reset All Settings resetting the toggle but keeping models (R73). The pane is
/// rendered in light and dark into `.build/screenshots/ai-settings/` for the visual review.
@MainActor
struct AISettingsTests {
    static let model = LocalModelManifest(
        id: "qwen3-4b-instruct-2507-4bit",
        displayName: "Qwen3 4B Instruct",
        status: .locked,
        role: .standard,
        repo: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
        revision: "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b",
        files: [.init(name: "model.safetensors", size: 2_274_519_691, sha256: "00")],
        license: .init(
            id: "apache-2.0",
            name: "Apache-2.0",
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507")!,
            upstreamRepo: "Qwen/Qwen3-4B-Instruct-2507",
        ),
        memoryBytes: 3_000_000_000,
    )

    /// Foundation Models stand-in with a fixed availability.
    struct FixedProvider: LanguageModelProvider, ModelTaskHandler {
        let id = ProviderID.foundationModels
        let answer: ProviderAvailability

        func availability() async -> ProviderAvailability {
            answer
        }

        func sectionLabels(_: SectionLabelTask, context _: CallContext)
            async throws(ProviderError) -> ModelResult<SectionLabelOutput>
        {
            throw .other
        }

        func metadata(_: MetadataTask, context _: CallContext)
            async throws(ProviderError) -> ModelResult<MetadataOutput>
        {
            throw .other
        }

        func ambiguousLines(_: AmbiguousLineTask, context _: CallContext)
            async throws(ProviderError) -> ModelResult<AmbiguousLineOutput>
        {
            throw .other
        }

        func setRequest(_: SetRequestTask, context _: CallContext)
            async throws(ProviderError) -> ModelResult<SetRequestOutput>
        {
            throw .other
        }
    }

    static func services(
        _ env: TestEnvironment,
        state: LocalModelState = .notInstalled,
        fm: ProviderAvailability = .available,
        memory: UInt64 = 32 << 30,
    ) -> (AIServices, ScriptedModelInstaller) {
        let installer = ScriptedModelInstaller(
            models: [model],
            states: [model.id: state],
            step: .milliseconds(20),
        )
        let services = AIServices(
            providers: [FixedProvider(answer: fm)],
            defaults: env.defaults,
            installer: installer,
            physicalMemory: memory,
        )
        return (services, installer)
    }

    @Test
    func `the toggle is on by default and drives the router gate`() throws {
        let env = try TestEnvironment()
        let (ai, _) = Self.services(env)
        #expect(ai.preferences.useAI)
        #expect(ai.gate.isEnabled)

        ai.preferences.useAI = false
        #expect(!ai.gate.isEnabled)
        #expect(env.defaults.object(forKey: AIPreferences.useAIKey) as? Bool == false)
        // A relaunch reads it back.
        let again = AIPreferences(defaults: env.defaults, gate: AIGate())
        #expect(!again.useAI)
    }

    @Test
    func `nothing downloads without a click, then a click walks to installed`() async throws {
        let env = try TestEnvironment()
        let (ai, installer) = Self.services(env)
        await ai.models.refresh()
        #expect(ai.models.snapshot.state(of: Self.model.id) == .notInstalled)
        #expect(await installer.actions.isEmpty)
        #expect(ModelCard.stateText(.notInstalled) == "Not downloaded")
        #expect(ByteFormat.size(Self.model.downloadBytes) == "2.27 GB")
        #expect(ByteFormat.size(Self.model.memoryBytes) == "3 GB")
        #expect(ModelCard.badge(.locked) == nil)
        #expect(ModelCard.badge(.candidate) == "Candidate")

        var summaries: [ModelDownloadSummary] = []
        ai.models.onDownloadFinished = { summaries.append($0) }
        ai.models.start()
        ai.models.download(Self.model.id)
        try await Self.waitUntil { ai.models.snapshot.state(of: Self.model.id) == .installed }
        try await Self.waitUntil { summaries.count == 1 }
        #expect(await installer.actions == ["download:\(Self.model.id)"])
        #expect(summaries.map(\.result) == [.completed])
        #expect(summaries.first?.kind == .curated)
        #expect(ai.models.snapshot.activeModelID == Self.model.id)
        ai.models.stop()
    }

    @Test
    func `the licence link is read aloud in words, not as an SPDX id`() {
        // Apple's audit flags "Apache-2.0" as a label that is not human-readable.
        #expect(AISettingsView.licenseLabel(Self.model.license.name) == "Apache 2.0 license")
    }

    @Test
    func `delete removes the model at once after the confirmation`() async throws {
        let env = try TestEnvironment()
        let (ai, installer) = Self.services(env, state: .installed)
        await ai.models.delete(Self.model.id)
        #expect(ai.models.snapshot.state(of: Self.model.id) == .notInstalled)
        #expect(await installer.actions == ["delete:\(Self.model.id)"])
        #expect(AISettingsView.deleteMessage(Self.model).contains("at once"))
    }

    @Test
    func `under 16 GB the model is an opt-in that the quiet links do not suggest`() async throws {
        let env = try TestEnvironment()
        let low = Self.services(env, memory: 8 << 30).0
        let roomy = Self.services(env, memory: 16 << 30).0
        await low.models.refresh()
        await roomy.models.refresh()
        #expect(low.models.isLowMemory && !low.models.suggestsDownload)
        #expect(!roomy.models.isLowMemory && roomy.models.suggestsDownload)
        #expect(ModelCard.lowMemoryNote(Self.model).contains("about 3 GB of memory"))
        #expect(ModelCard.lowMemoryNote(Self.model).contains("20-30 seconds per song"))
        // The review sheet footer's quiet link follows it.
        let missing: [ProviderKind: ProviderAvailability] = [
            .mlx: .unavailable(.notInstalled), .foundationModels: .available,
        ]
        for suggests in [true, false] {
            let footer = PasteFooter.make(
                status: .finished,
                reports: [:],
                aiEnabled: true,
                availability: missing,
                suggestsDownload: suggests,
            )
            #expect(footer.showsDownloadLink == suggests)
        }
        // Installed: nothing left to suggest.
        let installed = Self.services(env, state: .installed).0
        await installed.models.refresh()
        #expect(!installed.models.suggestsDownload)
    }

    @Test(arguments: [
        (UnavailableCause.appleIntelligenceNotEnabled, true),
        (.modelNotReady, true),
        (.deviceNotEligible, false),
        (.unknown, true),
    ])
    func `the Apple Intelligence note follows its reason`(
        cause: UnavailableCause,
        opensSettings: Bool,
    ) async throws {
        let env = try TestEnvironment()
        let (ai, _) = Self.services(env, fm: .unavailable(cause))
        await ai.refreshAvailability()
        let note = try #require(ai.foundationModelsNote)
        #expect(note.opensSettings == opensSettings)
        #expect(note == AIAvailabilityCopy.note(for: cause))
    }

    @Test
    func `reset all settings turns AI back on and keeps downloaded models`() async throws {
        let env = try TestEnvironment()
        var dependencies = env.dependencies(
            location: env.location(),
            override: env.libraryURL,
            remember: false,
        )
        let (ai, installer) = Self.services(env, state: .installed)
        dependencies.ai = ai
        let app = AppModel(dependencies: dependencies)
        await app.start()
        app.ai.preferences.useAI = false

        app.resetAllSettings()

        #expect(app.ai.preferences.useAI)
        #expect(app.ai.gate.isEnabled)
        #expect(env.defaults.object(forKey: AIPreferences.useAIKey) == nil)
        await app.ai.models.refresh()
        #expect(app.ai.models.snapshot.state(of: Self.model.id) == .installed)
        #expect(await installer.actions.isEmpty)
        #expect(DataSettingsView.resetMessage.contains("downloaded AI models"))
    }

    @Test
    func `the pane renders every model state in light and dark`() async throws {
        let env = try TestEnvironment()
        struct Case {
            var name: String
            var state: LocalModelState
            var fm: ProviderAvailability = .available
            var memory: UInt64 = 32 << 30
        }
        let downloading = LocalModelState.downloading(
            received: 912_000_000,
            total: Self.model.downloadBytes,
        )
        let cases = [
            Case(name: "no-model", state: .notInstalled),
            Case(name: "downloading", state: downloading),
            Case(name: "installed", state: .installed),
            Case(name: "low-ram", state: .notInstalled, memory: 8 << 30),
            Case(
                name: "fm-off",
                state: .failed(.network),
                fm: .unavailable(.appleIntelligenceNotEnabled),
            ),
        ]
        for item in cases {
            let (ai, _) = Self.services(env, state: item.state, fm: item.fm, memory: item.memory)
            await ai.models.refresh()
            await ai.refreshAvailability()
            for dark in [false, true] {
                let view = AISettingsView(
                    ai: ai,
                    workspace: NSWorkspaceActions(),
                    services: .inert(),
                )
                .frame(width: 560, height: 640)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: 560, height: 640)
                host.layoutSubtreeIfNeeded()
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let image = try #require(rep.cgImage)
                #expect(image.width >= 560)
                try DiagramSnapshotTests.writePNG(image, to: Self.directory.appending(
                    path: "\(item.name)-\(dark ? "dark" : "light").png",
                ))
            }
        }
    }

    /// `<repo>/.build/screenshots/ai-settings`.
    static var directory: URL {
        DiagramSnapshotTests.screenshotDirectory
            .deletingLastPathComponent()
            .appending(path: "ai-settings", directoryHint: .isDirectory)
    }

    static func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool,
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
