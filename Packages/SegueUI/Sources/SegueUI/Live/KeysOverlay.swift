#if os(macOS)
    import Shows
    import SwiftUI

    /// The stage's keyboard help (`?`, WS2a 3.7, A39): every command and its keys from the
    /// live bindings, in two columns, readable from 3 m. Non-modal: Esc or `?` closes it, and
    /// any other bound key closes it and still runs. No motion (none with Reduce Motion
    /// either: it simply appears).
    struct KeysOverlay: View {
        let groups: [KeyHelp.Group]

        var body: some View {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Keyboard Shortcuts", bundle: #bundle)
                        .font(SchibstedGrotesk.extraBold.font(size: 28))
                        .tracking(Theme.tracking.title * 28)
                        .foregroundStyle(Theme.color.ink)
                    Spacer(minLength: 24)
                    Text("Esc or ? closes", bundle: #bundle)
                        .font(SchibstedGrotesk.medium.font(size: 16))
                        .foregroundStyle(Theme.color.muted)
                }
                HStack(alignment: .top, spacing: 48) {
                    column(Array(groups.prefix(2)))
                    column(Array(groups.dropFirst(2)))
                }
                Text("Change keys in bindings.json (Help > Keyboard Shortcuts)", bundle: #bundle)
                    .font(SchibstedGrotesk.medium.font(size: 16))
                    .foregroundStyle(Theme.color.muted)
            }
            .padding(32)
            .frame(maxWidth: 1080)
            .background(StagePanelBackground(radius: 16))
            .padding(.horizontal, 48)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(uiString("Keyboard Shortcuts"))
            .accessibilityIdentifier(AccessibilityID.keysOverlay)
        }

        private func column(_ groups: [KeyHelp.Group]) -> some View {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title.uppercased())
                            .font(SchibstedGrotesk.bold.font(size: 15))
                            .tracking(0.6)
                            .foregroundStyle(Theme.color.muted)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.rows, id: \.command) { row in
                            KeysOverlayRow(row: row)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Next Song   → Space" with the keys drawn as keycaps.
    private struct KeysOverlayRow: View {
        let row: KeyHelp.Row

        private var spokenKeys: String {
            row.keys.isEmpty ? "not bound" : row.keys.joined(separator: ", ")
        }

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(row.title)
                    .font(SchibstedGrotesk.medium.font(size: 18))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if row.keys.isEmpty {
                    Text("Not bound", bundle: #bundle)
                        .font(SchibstedGrotesk.medium.font(size: 18))
                        .foregroundStyle(Theme.color.muted)
                } else {
                    HStack(spacing: 6) {
                        ForEach(row.keys, id: \.self) { key in
                            Text(key)
                                .font(SchibstedGrotesk.semiBold.font(size: 18))
                                .foregroundStyle(Theme.color.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Theme.color.controlBorder, lineWidth: 1),
                                )
                        }
                    }
                    .fixedSize()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(row.title): \(spokenKeys)"))
            .accessibilityIdentifier(AccessibilityID.keysOverlayRow)
        }
    }
#endif
