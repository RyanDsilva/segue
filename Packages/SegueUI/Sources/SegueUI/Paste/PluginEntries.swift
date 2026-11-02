#if os(macOS)
    import Foundation
    import Library
    import ModelPort
    import Plugins
    import Services
    import SwiftUI

    // P9-4 spec 4.3: the UI hosting of the Personal build's web import and song search, on
    // the `advancedSection` pattern. SegueUI never imports the personal package; the app
    // fills these entries in the Personal build only, and every entry point asks "is the
    // entry non-nil?", never a build flag. With both nil (App Store) no menu item, button,
    // lone-URL route, link drop or extra file type exists.

    /// The plugin UI the app composed for this launch.
    @MainActor
    public struct PluginEntries {
        public var webImport: WebImportEntry?
        public var songSearch: SongSearchEntry?

        public init(webImport: WebImportEntry? = nil, songSearch: SongSearchEntry? = nil) {
            self.webImport = webImport
            self.songSearch = songSearch
        }
    }

    /// Import from Web Page (spec 8, 11.1-11.5).
    @MainActor
    public struct WebImportEntry {
        /// The web address field above the New Song text area (spec 11.3).
        public var field: @MainActor (ImportHost) -> AnyView
        /// Settings > Data's section (Clear Site Data, spec 8.6); nil shows none.
        public var settings: (@MainActor () -> AnyView)?
        /// Saved web page files this entry reads (spec 8.1): Import Songs… offers them too.
        public var fileExtensions: [String]

        public init(
            field: @escaping @MainActor (ImportHost) -> AnyView,
            settings: (@MainActor () -> AnyView)? = nil,
            fileExtensions: [String],
        ) {
            self.field = field
            self.settings = settings
            self.fileExtensions = fileExtensions
        }

        /// Whether a dropped or chosen file is a saved web page this entry reads.
        public func acceptsFile(_ url: URL) -> Bool {
            url.isFileURL && fileExtensions.contains(url.pathExtension.lowercased())
        }
    }

    /// Find Lyrics (spec 6.4).
    @MainActor
    public struct SongSearchEntry {
        /// The sheet's content, shown in the review sheet's search phase.
        public var sheet: @MainActor (ImportHost) -> AnyView

        public init(sheet: @escaping @MainActor (ImportHost) -> AnyView) {
            self.sheet = sheet
        }
    }

    /// What the plugin views get from SegueUI: the open review sheet to hand a song to, and
    /// the app services they may use. Built by the sheet for each presentation.
    @MainActor
    public struct ImportHost {
        /// The sheet's model: `submitSource` moves it to review; its pending web input says
        /// what to fetch at once (a lone pasted URL, a dropped link, a saved page).
        public let review: PasteReviewModel
        /// The AI router (R194: the film title split); deterministic-only during a show.
        public var router: Router
        /// The library a search result is checked against ("In your library", spec 5.3).
        public var nearDuplicates: NearDuplicateIndex?
        /// Records one analytics event (rows 33-35).
        public var record: @MainActor (AnalyticsEvent) -> Void
        /// Opens a page in the user's browser.
        public var open: @MainActor (URL) -> Void
        /// Closes the sheet, writing nothing.
        public var cancel: @MainActor () -> Void

        public init(
            review: PasteReviewModel,
            router: Router,
            nearDuplicates: NearDuplicateIndex?,
            record: @escaping @MainActor (AnalyticsEvent) -> Void,
            open: @escaping @MainActor (URL) -> Void,
            cancel: @escaping @MainActor () -> Void,
        ) {
            self.review = review
            self.router = router
            self.nearDuplicates = nearDuplicates
            self.record = record
            self.open = open
            self.cancel = cancel
        }
    }

    /// Something to read at once when the New Song sheet opens (spec 11.4, 11.5, 8.1).
    public enum PendingWebInput: Equatable, Sendable {
        /// A page address and where it came from.
        case address(URL, WebImportEntryPoint)
        /// A saved page file (`.html`, `.htm`, `.webarchive`).
        case file(URL)

        public var entry: WebImportEntryPoint {
            switch self {
            case let .address(_, entry): entry
            case .file: .savedFile
            }
        }
    }

    /// The lone-URL rule (spec 11.4): the text is only one `http(s)` address after trimming.
    public enum LoneWebAddress {
        public static func url(in text: String) -> URL? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
                  let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.host(percentEncoded: false), host.contains(".")
            else { return nil }
            return url
        }
    }
#endif
