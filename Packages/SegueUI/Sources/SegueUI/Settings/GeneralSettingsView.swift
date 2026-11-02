#if os(macOS)
    import Darwin
    import Setlists
    import SwiftUI

    /// Settings > General: the library folder, where to change it and Show Library in Finder
    /// (the only place it appears in Settings), and the default changeover between songs.
    struct GeneralSettingsView: View {
        let app: AppModel
        @AppStorage(ChangeoverSetting.defaultsKey) private var changeover = 0

        var body: some View {
            Form {
                Section(uiString("Library")) {
                    LabeledContent(uiString("Library folder")) {
                        Text(libraryPath)
                            .foregroundStyle(app.session == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(app.session?.root.url.path(percentEncoded: false) ?? "")
                            .accessibilityIdentifier(AccessibilityID.settingsLibraryPath)
                    }
                    HStack {
                        Button(uiString("Change…")) {
                            let choose = { Task { await app.chooseLibrary() } }
                            if let session = app.session {
                                session.library.navigate { _ = choose() }
                            } else {
                                _ = choose()
                            }
                        }
                        .disabled(!app.canSwitchLibrary)
                        .help(app
                            .canSwitchLibrary ? "" :
                            uiString("End the show before switching libraries."))
                        .accessibilityIdentifier(AccessibilityID.settingsChangeLibrary)
                        Button(uiString("Show Library in Finder")) { app.session?.revealLibrary() }
                            .disabled(app.session == nil)
                            .accessibilityIdentifier(AccessibilityID.settingsShowLibrary)
                    }
                    SettingsNote(text: "Songs are plain ChordPro files in this folder. Back it up "
                        + "like any folder; Time Machine works.")
                }
                Section(uiString("Setlists")) {
                    Stepper(
                        value: Binding(
                            get: { ChangeoverSetting.clamped(changeover) },
                            set: { changeover = ChangeoverSetting.clamped($0) },
                        ),
                        in: ChangeoverSetting.range,
                        step: ChangeoverSetting.step,
                    ) {
                        LabeledContent(
                            uiString("Changeover between songs"),
                            value: SetlistTiming.formatChangeover(
                                TimeInterval(ChangeoverSetting.clamped(changeover)),
                            ),
                        )
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsChangeover)
                    SettingsNote(text: "Added after every song but the last of each part, in "
                        + "every setlist total. A setlist can set its own.")
                }
            }
            .formStyle(.grouped)
            .settingsPaneHeight(minimum: 340)
        }

        /// `~/Music/Segue`, with the real home folder (not the sandbox container) as `~`.
        private var libraryPath: String {
            guard let url = app.session?.root.url else { return "No library open" }
            return Self.abbreviated(url.path(percentEncoded: false))
        }

        static func abbreviated(_ path: String, home: String? = realHome) -> String {
            var trimmed = path
            if trimmed.count > 1, trimmed.hasSuffix("/") {
                trimmed.removeLast()
            }
            guard let home, trimmed == home || trimmed.hasPrefix(home + "/") else {
                return trimmed
            }
            return "~" + trimmed.dropFirst(home.count)
        }

        /// The user's home folder (the sandbox points `NSHomeDirectory` into the container).
        static var realHome: String? {
            guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return nil }
            return String(cString: dir)
        }
    }
#endif
