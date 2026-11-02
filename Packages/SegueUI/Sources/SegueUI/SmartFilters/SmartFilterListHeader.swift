#if os(macOS)
    import Library
    import SwiftUI

    /// Above the song list while a smart filter is shown: its name, how many songs it
    /// matches, and Edit... for a saved filter. Nothing while the list shows every song.
    struct SmartFilterListHeader: View {
        let session: LibrarySession

        var body: some View {
            let scope = session.library.scope
            if scope.isFiltered {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scope.title)
                            .font(SchibstedGrotesk.extraBold.font(size: 18))
                            .foregroundStyle(Theme.color.ink)
                            .lineLimit(1)
                        Text(subtitle(scope))
                            .font(Theme.font.body)
                            .foregroundStyle(Theme.color.muted)
                    }
                    Spacer(minLength: 4)
                    if case let .smartFilter(filter) = scope {
                        Button(uiString("Edit…")) { session.smartFilters.editing = .edit(filter.id)
                        }
                        .buttonStyle(.segueSecondary)
                        .help(uiString("Edit this smart filter’s conditions"))
                        .accessibilityIdentifier(AccessibilityID.smartFilterEdit)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.smartFilterListHeader)
            }
        }

        private func subtitle(_ scope: LibraryScope) -> String {
            let count = session.library.scoped(session.library.catalog).count
            let songs = count == 1 ? "1 song" : "\(count) songs"
            switch scope {
            case .missingEssentials:
                return songs + " without a key, length or tempo"
            case let .smartFilter(filter):
                let conditions = filter.conditions.count
                return songs + " · " +
                    (conditions == 1 ? "1 condition" : "\(conditions) conditions")
            case .all:
                return songs
            }
        }
    }
#endif
