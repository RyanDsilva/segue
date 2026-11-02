#if os(macOS)
    import SwiftUI

    /// Settings > Data: Rebuild Index, the Welcome songs and the resets. Every control that
    /// changes the library waits for an open library and no show.
    struct DataSettingsView: View {
        let app: AppModel
        @State private var status: String?
        @State private var removal: SeedRemovalPlan?
        @State private var confirmingReset = false
        @State private var working = false

        var body: some View {
            Form {
                Section(uiString("Library")) {
                    LabeledContent(uiString("Archive")) {
                        HStack(spacing: 8) {
                            if app.isExporting {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel(uiString("Exporting"))
                                    .accessibilityIdentifier(AccessibilityID.exportProgress)
                            }
                            Button(uiString("Export Library Archive…")) {
                                Task { await app.exportLibraryArchive() }
                            }
                            .disabled(!app.canExportArchive)
                            .accessibilityIdentifier(AccessibilityID.exportArchive)
                        }
                    }
                    SettingsNote(text: "One zip of your songs, setlists, shows and filters, "
                        + "as they are in the library folder.")
                    LabeledContent(uiString("Index")) {
                        Button(uiString("Rebuild Index")) {
                            guard let session = app.session else { return }
                            Task { await session.library.rebuildIndex() }
                        }
                        .disabled(!app.canChangeLibraryData)
                        .accessibilityIdentifier(AccessibilityID.settingsRebuildIndex)
                    }
                    SettingsNote(text: "Rebuilds Segue's search index from the song files. "
                        + "Your songs are not changed.")
                    libraryLocationNotes
                }
                Section(uiString("Welcome songs")) {
                    HStack {
                        Button(uiString("Add Welcome Songs")) { addWelcomeSongs() }
                            .accessibilityIdentifier(AccessibilityID.settingsAddWelcome)
                        Button(uiString("Remove Welcome Songs…")) { askToRemove() }
                            .accessibilityIdentifier(AccessibilityID.settingsRemoveWelcome)
                    }
                    .disabled(!app.canChangeLibraryData || working)
                    SettingsNote(text: "Four songs and a setlist written for Segue. Removing "
                        + "them moves them to the Trash and keeps any you edited.")
                }
                Section(uiString("Reset")) {
                    HStack {
                        Button(uiString("Reset Tips")) {
                            app.resetTips()
                            status = "Tips will show again after you restart Segue."
                        }
                        .accessibilityIdentifier(AccessibilityID.settingsResetTips)
                        Button(uiString("Reset All Settings…")) { confirmingReset = true }
                            .accessibilityIdentifier(AccessibilityID.settingsResetAll)
                    }
                    SettingsNote(text: "Reset All Settings keeps your library and your Privacy "
                        + "choices.")
                }
                if let status {
                    Text(status)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.settingsDataStatus)
                }
                SettingsGuideHelp(page: .backUp)
            }
            .formStyle(.grouped)
            .settingsPaneHeight(minimum: 420)
            .confirmationDialog(
                removal?.headline ?? "",
                isPresented: Binding(
                    get: { removal != nil },
                    set: {
                        if !$0 {
                            removal = nil
                        }
                    },
                ),
                titleVisibility: .visible,
                presenting: removal,
            ) { plan in
                Button(uiString("Move to Trash"), role: .destructive) { remove(plan) }
                    .accessibilityIdentifier(AccessibilityID.settingsRemoveWelcomeConfirm)
                Button(uiString("Cancel"), role: .cancel) {}
            } message: { plan in
                Text(plan.keptNote ?? uiString("You can put them back from the Trash."))
            }
            .confirmationDialog(
                "Reset all settings?",
                isPresented: $confirmingReset,
                titleVisibility: .visible,
            ) {
                Button(uiString("Reset All Settings"), role: .destructive) {
                    app.resetAllSettings()
                    status = "Settings are back to their defaults. Tips will show again after "
                        + "you restart Segue."
                }
                .accessibilityIdentifier(AccessibilityID.settingsResetAllConfirm)
                Button(uiString("Cancel"), role: .cancel) {}
            } message: {
                Text(Self.resetMessage)
            }
        }

        /// The file-sync warning while it applies (P9-6 5.4, whether or not the banner was
        /// dismissed), and the lost cross-flavor lock when the shared state is unreachable.
        @ViewBuilder private var libraryLocationNotes: some View {
            if let warning = app.session?.folderKind.warning {
                SettingsNote(text: warning)
                    .accessibilityIdentifier(AccessibilityID.settingsFileSyncNote)
            }
            if !app.dependencies.libraryState.isShared {
                SettingsNote(text: Self.unsharedStateNote)
            }
        }

        static let unsharedStateNote = "Segue could not reach the storage both Segue apps "
            + "share, so another copy of Segue on this Mac could open this library at the same "
            + "time."

        static let resetMessage = "Resets: Live settings, Appearance, Instrument, Audio, "
            + "Export, the AI setting, the last Settings pane and the tips.\nKeeps: your "
            + "Privacy choices, the library folder and its songs, the Welcome songs, What's "
            + "New and review history, your chord shapes and key bindings, and downloaded AI "
            + "models."

        private func addWelcomeSongs() {
            working = true
            Task {
                status = await app.addWelcomeSongsFromSettings()
                working = false
            }
        }

        private func askToRemove() {
            working = true
            Task {
                let plan = await app.welcomeRemovalPlan()
                working = false
                if let plan, !plan.isEmpty {
                    removal = plan
                } else {
                    status = plan?.keptNote.map { "Nothing to remove. \($0)" }
                        ?? "There are no Welcome songs in this library."
                }
            }
        }

        private func remove(_ plan: SeedRemovalPlan) {
            working = true
            Task {
                status = await app.removeWelcomeSongs(plan)
                working = false
            }
        }
    }
#endif
