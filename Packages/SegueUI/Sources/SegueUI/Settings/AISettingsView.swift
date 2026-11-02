#if os(macOS)
    import ModelPort
    import Services
    import SwiftUI

    /// Settings > AI (spec section 10, R73, R93): the one "Use AI" toggle, Apple Intelligence's
    /// status with the R69 note, the curated local model card (download only on a click, size,
    /// license, memory need and free disk shown first, R66; the low-memory note under 16 GB,
    /// R68; Delete removes directly after a confirmation, R99), and, in the Personal build
    /// only, Advanced custom models (R62).
    struct AISettingsView: View {
        let ai: AIServices
        let workspace: any WorkspaceActions
        let services: ServicesHub
        @State private var confirmingDelete: LocalModelManifest?

        var body: some View {
            @Bindable var preferences = ai.preferences
            // As tall as its form: the model card loads after the window has opened, and
            // with a fixed height its notes pushed Download under the Help button.
            SettingsPaneHeight(minimum: 460) {
                Form {
                    Section {
                        Toggle(
                            uiString("Use AI to refine pastes and set requests"),
                            isOn: $preferences.useAI,
                        )
                        .accessibilityIdentifier(AccessibilityID.settingsAIUseAI)
                        SettingsNote(text: Self.toggleNote)
                    }
                    Section(uiString("Apple Intelligence")) {
                        appleIntelligence
                    }
                    .disabled(!preferences.useAI)
                    Section {
                        ForEach(ai.models.snapshot.models) { model in
                            ModelCard(
                                model: model,
                                state: ai.models.snapshot.state(of: model.id),
                                freeDisk: ai.models.snapshot.freeDiskBytes,
                                isLowMemory: ai.models.isLowMemory,
                                appleIntelligence: ai.availability[.foundationModels],
                                workspace: workspace,
                                download: { ai.models.download(model.id) },
                                cancel: { ai.models.cancel(model.id) },
                                delete: { confirmingDelete = model },
                            )
                        }
                        if ai.models.installer == nil {
                            SettingsNote(text: "Local models are not available in this build.")
                        }
                        if let error = ai.models.deleteError {
                            Text(Self.deleteErrorText(error))
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                        SettingsNote(
                            text: Self.modelNote(ai.availability[.foundationModels]),
                        )
                    } header: {
                        Text("Local model", bundle: #bundle)
                    }
                    if let advanced = ai.advancedSection {
                        Section(uiString("Advanced")) {
                            advanced()
                        }
                        .accessibilityIdentifier(AccessibilityID.settingsAIAdvanced)
                    }
                    SettingsGuideHelp(page: .ai)
                }
                .formStyle(.grouped)
            }
            .task {
                ai.models.onDownloadFinished = { services.record(.aiModelDownload($0)) }
                ai.models.start()
                await ai.models.refresh()
                await ai.refreshAvailability()
            }
            .onDisappear { ai.models.stop() }
            .confirmationDialog(
                confirmingDelete.map { uiString("Delete \($0.displayName)?") } ?? "",
                isPresented: Binding(
                    get: { confirmingDelete != nil },
                    set: {
                        if !$0 {
                            confirmingDelete = nil
                        }
                    },
                ),
                titleVisibility: .visible,
                presenting: confirmingDelete,
            ) { model in
                Button(uiString("Delete"), role: .destructive) {
                    Task { await ai.models.delete(model.id) }
                }
                .accessibilityIdentifier(AccessibilityID.settingsAIDeleteConfirm)
                Button(uiString("Cancel"), role: .cancel) {}
            } message: { model in
                Text(Self.deleteMessage(model))
            }
        }

        @ViewBuilder private var appleIntelligence: some View {
            let status = switch ai.availability[.foundationModels] {
            case .available: "Ready"
            case .unavailable: "Not available"
            case nil: "Checking…"
            }
            LabeledContent(uiString("Status")) {
                Text(status)
                    .accessibilityIdentifier(AccessibilityID.settingsAIAppleIntelligence)
            }
            if let note = ai.foundationModelsNote {
                SettingsNote(text: note.text)
                if note.opensSettings {
                    Button(AIAvailabilityCopy.openSettingsTitle) {
                        AIAvailabilityCopy.openSettings(with: workspace)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsAIOpenSystemSettings)
                }
            }
        }

        static let toggleNote = "Segue sorts pasted chord sheets into sections and reads set "
            + "requests on this Mac. Nothing you paste leaves it. Off: Segue uses its own rules "
            + "only."

        /// What the downloaded model is used for; Apple Intelligence is named as the
        /// fallback only where it is not known to be unavailable.
        static func modelNote(_ appleIntelligence: ProviderAvailability?) -> String {
            let use = if case .unavailable = appleIntelligence {
                "When the local model is downloaded, Segue uses it for pastes and set requests."
            } else {
                "When the local model is downloaded, Segue uses it first and Apple "
                    + "Intelligence otherwise."
            }
            return use + " It loads only while it works on a paste or a set request, never "
                + "during a show."
        }

        /// The licence link read aloud: an SPDX id such as "Apache-2.0" is not human-readable
        /// to VoiceOver (Apple's audit), so it is spoken as "Apache 2.0 license"; Voice
        /// Control still matches the visible words.
        static func licenseLabel(_ spdx: String) -> String {
            "\(spdx.replacingOccurrences(of: "-", with: " ")) license"
        }

        static func deleteMessage(_ model: LocalModelManifest) -> String {
            "This removes the model's files from this Mac at once, for both Segue apps. You can "
                + "download it again (\(ByteFormat.size(model.downloadBytes)))."
        }

        static func deleteErrorText(_ error: LocalModelStoreError) -> String {
            switch error {
            case .busy: "Cancel the download before deleting the model."
            case .fileSystem, .unavailable, .unknownModel: "Segue could not delete the model."
            }
        }
    }

    /// One downloadable model: facts first, then its state and the one action that fits.
    struct ModelCard: View {
        let model: LocalModelManifest
        let state: LocalModelState
        let freeDisk: Int64?
        let isLowMemory: Bool
        /// Apple Intelligence as last read (nil: not read yet); the low-memory note's claim
        /// about it follows this.
        var appleIntelligence: ProviderAvailability?
        let workspace: any WorkspaceActions
        let download: () -> Void
        let cancel: () -> Void
        let delete: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.displayName)
                        .font(.headline)
                    if let badge = Self.badge(model.status) {
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(.secondary.opacity(0.5)))
                    }
                    Spacer()
                    Text(Self.stateText(state))
                        .font(.callout)
                        .foregroundStyle(stateIsProblem ? AnyShapeStyle(.red)
                            : AnyShapeStyle(.secondary))
                        .accessibilityIdentifier(AccessibilityID.settingsAIModelState)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    fact(
                        "Download",
                        ByteFormat.size(model.downloadBytes),
                        id: AccessibilityID.settingsAIModelSize,
                    )
                    fact(
                        "Memory",
                        "About \(ByteFormat.size(model.memoryBytes)) while it works",
                        id: AccessibilityID.settingsAIModelMemory,
                    )
                    GridRow {
                        Text("License", bundle: #bundle).foregroundStyle(.secondary)
                        Button(model.license.name) { workspace.open(model.license.url) }
                            .buttonStyle(.link)
                            .help(model.license.upstreamRepo)
                            .accessibilityLabel(AISettingsView.licenseLabel(model.license.name))
                            .accessibilityIdentifier(AccessibilityID.settingsAIModelLicense)
                    }
                    if let freeDisk {
                        fact(
                            "Free on this Mac",
                            ByteFormat.size(freeDisk),
                            id: AccessibilityID.settingsAIFreeDisk,
                        )
                    }
                }
                .font(.callout)
                if isLowMemory {
                    Label(
                        Self.lowMemoryNote(
                            model,
                            state: state,
                            appleIntelligence: appleIntelligence,
                        ),
                        systemImage: "memorychip",
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.settingsAILowMemory)
                }
                actions
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.settingsAIModel(model.id))
        }

        @ViewBuilder private var actions: some View {
            switch state {
            case .failed, .notInstalled:
                // R93: a quiet link, never a prompt.
                Button(
                    state == .notInstalled ? uiString("Download") : uiString("Try Again"),
                    action: download,
                )
                .buttonStyle(.link)
                .accessibilityIdentifier(AccessibilityID.settingsAIDownload)
            case let .paused(received, total):
                HStack(spacing: 16) {
                    Button(uiString("Resume Download"), action: download)
                        .buttonStyle(.link)
                        .accessibilityIdentifier(AccessibilityID.settingsAIDownload)
                    Button(uiString("Delete…"), action: delete)
                        .buttonStyle(.link)
                        .accessibilityIdentifier(AccessibilityID.settingsAIDelete)
                }
                .help(uiString("""
                \(ByteFormat.size(received)) of \(ByteFormat.size(total)) downloaded
                """))
            case let .downloading(received, total):
                HStack(spacing: 10) {
                    ProgressView(value: Double(received), total: Double(max(total, 1)))
                        .accessibilityIdentifier(AccessibilityID.settingsAIProgress)
                    Button(uiString("Cancel"), action: cancel)
                        .accessibilityIdentifier(AccessibilityID.settingsAICancel)
                }
            case .verifying:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier(AccessibilityID.settingsAIProgress)
            case .installed:
                Button(uiString("Delete…"), action: delete)
                    .accessibilityIdentifier(AccessibilityID.settingsAIDelete)
            case .otherAppDownloading:
                EmptyView()
            }
        }

        private var stateIsProblem: Bool {
            if case .failed = state {
                return true
            }
            return false
        }

        private func fact(_ label: String, _ value: String, id: String) -> some View {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                Text(value)
                    .monospacedDigit()
                    .accessibilityIdentifier(id)
            }
        }

        /// "Candidate" until R64 locks the model.
        static func badge(_ status: LocalModelManifest.Status) -> String? {
            switch status {
            case .candidate: "Candidate"
            case .custom: "Custom"
            case .locked: nil
            }
        }

        static func stateText(_ state: LocalModelState) -> String {
            switch state {
            case .notInstalled:
                "Not downloaded"
            case let .downloading(received, total):
                "Downloading \(ByteFormat.size(received)) of \(ByteFormat.size(total))"
            case let .paused(received, total):
                "Paused at \(ByteFormat.size(received)) of \(ByteFormat.size(total))"
            case .verifying:
                "Checking files…"
            case .installed:
                "Downloaded"
            case let .failed(failure):
                failureText(failure)
            case .otherAppDownloading:
                "Downloading in the other Segue app"
            }
        }

        static func failureText(_ failure: ModelDownloadFailure) -> String {
            switch failure {
            case .network: "Download stopped: no connection"
            case .checksum: "Download failed its check"
            case .disk: "Not enough free space"
            case .other: "Download failed"
            }
        }

        /// R68, R120: on Macs under 16 GB the note says what the model costs and never
        /// blocks the download. What it says about Apple Intelligence is only what is true:
        /// the default when it is available, the only other way when it is not, nothing
        /// before it has been read or once the model is installed (Segue then uses it first).
        static func lowMemoryNote(
            _ model: LocalModelManifest,
            state: LocalModelState,
            appleIntelligence: ProviderAvailability?,
        ) -> String {
            let memory = ByteFormat.size(model.memoryBytes)
            let cost = "about \(memory) of memory while it works and takes roughly 20-30 "
                + "seconds per song here, and other apps may slow down."
            if state.isInstalled {
                return "On this Mac the local model needs \(cost)"
            }
            switch appleIntelligence {
            case .available:
                return "Optional on this Mac: Segue uses Apple Intelligence. The local model "
                    + "needs \(cost)"
            case .unavailable:
                return "Apple Intelligence is not available, so the local model is the only "
                    + "on-device AI here. It needs \(cost)"
            case nil:
                return "The local model needs \(cost)"
            }
        }
    }

    /// Download and memory sizes as Finder shows them (decimal: 2.27 GB).
    enum ByteFormat {
        static func size(_ bytes: Int64) -> String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            formatter.allowedUnits = [.useMB, .useGB]
            return formatter.string(fromByteCount: bytes)
        }
    }
#endif
