#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// The menu bar (WS2a 3.5): App, File, Library, Setlist and Help menus, each its own
    /// `Commands` type. Key equivalents come from `MenuShortcuts`. Later workstreams fill
    /// `AppHooks` instead of editing these menus.
    public struct SegueCommands: Commands {
        let app: AppModel

        public init(app: AppModel) {
            self.app = app
        }

        public var body: some Commands {
            AppInfoCommands()
            FileCommands(app: app)
            LibraryCommands(app: app)
            SetlistCommands(app: app)
            WindowCommands()
            HelpCommands(app: app)
        }
    }

    extension AppModel {
        /// A sheet, alert or prompt is up in the main window: commands that would act
        /// behind it (start a show, add to a setlist) wait.
        var isMainWindowBusy: Bool {
            guard let session else { return false }
            return session.isNamingNewSetlist || session.songTrashConfirmation != nil
                || session.library.pendingNavigation != nil || preShow != nil
                || pendingResume != nil || !pendingReorderReviews.isEmpty
                || startFailure != nil
        }

        /// The song a menu command acts on: the one selected in the focused song list, else
        /// the one whose detail or editor the Library shows.
        func menuSong(focused: SongID?) -> SongID? {
            guard let session, !isPerforming else { return nil }
            if let focused {
                return focused
            }
            guard session.section == .library || session.section == nil,
                  case let .song(id) = session.library.detail
            else { return nil }
            return id
        }

        /// The setlist whose builder is shown, if any.
        var shownSetlist: Setlist? {
            guard let session, case let .setlist(id) = session.section else { return nil }
            return session.setlists.setlist(id)
        }
    }
#endif
