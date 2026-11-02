#if os(macOS)
    import Shows
    import SwiftUI

    /// Identity of the Help > Keyboard Shortcuts window scene.
    public enum KeyboardShortcutsWindow {
        public static let id = "segue.shortcuts"
    }

    /// Help > Keyboard Shortcuts (WS2a 3.7): the main window's keys, generated from
    /// `MenuShortcuts` (the same table the menus use) plus the editor's own keys, and the
    /// stage's keys from the live bindings.
    public struct KeyboardShortcutsView: View {
        let stage: [KeyHelp.Group]
        let stageWarning: String?
        @Environment(\.openGuide) private var openGuide

        public init(stage: [KeyHelp.Group] = [], stageWarning: String? = nil) {
            self.stage = stage
            self.stageWarning = stageWarning
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Keyboard Shortcuts")
                        .font(Theme.font.title)
                        .tracking(Theme.tracking.title * 28)
                        .foregroundStyle(Theme.color.ink)
                    shortcutSection("Main window", id: AccessibilityID.shortcutsMainSection) {
                        ForEach(Self.menuGroups, id: \.menu) { menuGroup in
                            shortcutGroup(
                                menuGroup.menu,
                                rows: menuGroup.items.map { ($0.title, [$0.displayText]) },
                            )
                        }
                        shortcutGroup("Editor", rows: EditorKeys.rows.map { ($0.title, [$0.keys]) })
                    }
                    if !stage.isEmpty {
                        shortcutSection("On stage", id: AccessibilityID.shortcutsStageSection) {
                            if let stageWarning {
                                Label(stageWarning, systemImage: "exclamationmark.triangle.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(stage, id: \.title) { stageSection in
                                shortcutGroup(
                                    stageSection.title,
                                    rows: stageSection.rows.map { ($0.title, $0.keys) },
                                )
                            }
                            Text("Change stage keys in bindings.json, in Segue’s Application "
                                + "Support folder.")
                                .font(Theme.font.label)
                                .foregroundStyle(Theme.color.muted)
                        }
                    }
                    if let openGuide {
                        Button("All shortcuts in the Segue Guide") { openGuide(.keyboard) }
                            .buttonStyle(.link)
                            .accessibilityIdentifier(AccessibilityID.keyboardShortcutsGuide)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.color.ground)
            .accessibilityIdentifier(AccessibilityID.shortcutsWindow)
        }

        /// `MenuShortcuts` grouped by menu, in menu order.
        static var menuGroups: [(menu: String, items: [MenuShortcut])] {
            var groups: [(menu: String, items: [MenuShortcut])] = []
            for shortcut in MenuShortcuts.all {
                if let index = groups.firstIndex(where: { $0.menu == shortcut.menu }) {
                    groups[index].items.append(shortcut)
                } else {
                    groups.append((shortcut.menu, [shortcut]))
                }
            }
            return groups
        }

        private func shortcutSection(
            _ title: String,
            id: String,
            @ViewBuilder content: () -> some View,
        ) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                content()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
        }

        private func shortcutGroup(_ title: String, rows: [(String, [String])]) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.0)
                            .font(Theme.font.body)
                            .foregroundStyle(Theme.color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.1.isEmpty ? "Not bound" : row.1.joined(separator: "  "))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(row.1.isEmpty ? Theme.color.muted : Theme.color.ink)
                    }
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) { Hairline() }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// The Keyboard Shortcuts window's content: the stage keys come from the same binding
    /// table the stage uses (defaults plus `bindings.json`); a file that cannot be read
    /// shows the defaults with the stage's warning.
    public struct KeyboardShortcutsWindowContent: View {
        let app: AppModel

        public init(app: AppModel) {
            self.app = app
        }

        public var body: some View {
            let (table, warning) = loadBindings()
            KeyboardShortcutsView(stage: KeyHelp.groups(table), stageWarning: warning)
                .guideLinks(app.help)
        }

        private func loadBindings() -> (InputBindingTable, String?) {
            do {
                let loaded = try InputBindingTable.loadReporting(
                    from: app.dependencies.live.bindingsURL,
                    fileSystem: app.dependencies.fileSystem,
                )
                let warning: String? = if loaded.newerSchema != nil, loaded.skipped > 0 {
                    "Your key bindings file was saved by a newer version of Segue: "
                        + "\(loaded.skipped) of its bindings are not available in this "
                        + "version, so those keys keep their defaults."
                } else {
                    nil
                }
                return (loaded.table, warning)
            } catch {
                return (
                    .defaults,
                    "Your key bindings file could not be read "
                        + "(\(UserMessage.describe(error))), so the default keys are shown.",
                )
            }
        }
    }
#endif
