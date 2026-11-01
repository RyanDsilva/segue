// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A (core), C (dispatch).

import Foundation

/// Every argument-free live-mode action. Keyboard now, MIDI later (phase 6): input sources
/// map raw input to these through an `InputBindingTable`; nothing else needs to change when
/// a new input source arrives. (The spec's `ShowCommand`.)
///
/// The stage's session model is the single dispatcher: `.show` commands become a
/// `ShowAction` for `ShowController`, `.viewport` commands drive scroll and zoom, and
/// `.chrome` commands toggle overlays.
public enum LiveCommand: String, Sendable, Hashable, Codable, CaseIterable {
    case next
    case previous
    case scrollPageDown
    case scrollPageUp
    /// Page-turner pedals (R45): Page Down, and at the song's bottom the next song (at its
    /// top). The default for the Page Down key; arrows keep plain paging.
    case pageForward
    /// Page Up, and at the song's top the previous song (at its bottom).
    case pageBack
    case toggleAutoScroll
    case scrollFaster
    case scrollSlower
    /// Auto-scroll back to the top (paused).
    case restartScroll
    case skipCurrent
    case openSearch
    case playNextRequest
    /// Show or hide the request queue panel.
    case toggleRequests
    /// Show or hide the set order drawer (reorder, skip, un-skip).
    case toggleSidebar
    case zoomIn
    case zoomOut
    case resetZoom
    /// Cycles the current song's columns Auto -> 1 -> 2 -> 3 -> Auto (saved to the sidecar
    /// as `LivePrefs.columns`).
    case cycleColumns
    /// Asks for confirmation, then ends the show.
    case endShow
    /// Shows or hides the keyboard help overlay (`?`).
    case showKeys
    /// The stage metronome's pulse on or off (`M`, R90).
    case toggleMetronome
    /// The metronome's click on or off: rehearsals only, never a sound in a gig (`K`, R118).
    case toggleMetronomeClick
    /// Jump to the n-th shown pass of the song (keys 1-9, R148).
    case jumpToPass1
    case jumpToPass2
    case jumpToPass3
    case jumpToPass4
    case jumpToPass5
    case jumpToPass6
    case jumpToPass7
    case jumpToPass8
    case jumpToPass9
    /// Loop the current pass with a one-bar count-in: rehearsals only (`L`, R148).
    case toggleLoop
    /// The user-level bass-note view on or off, for anyone (`B`, P8-4, R158 Q3).
    case toggleBassNotes
    /// The user-level "Fills as tab" on or off: every saved fill as a mini tab instead of
    /// note names (`T`, P8-7 section 14.2, R168 Q8). Display only, Live and Rehearsal.
    case toggleFillTab
    /// Play bass, chords and click along from the current pass: rehearsals only (`P`, P8-6
    /// 10.4); a gig only flashes.
    case togglePlayAlong
    /// Singer view on stage on or off: lyrics only, chords hidden (`V`, P9-2 section 6.1).
    /// Remembered across shows; Live and Rehearsal alike.
    case toggleSingerView

    /// Who handles a command.
    public enum Scope: Sendable, Hashable {
        /// Changes show state: goes to `ShowController`.
        case show
        /// Scroll and zoom of the current song.
        case viewport
        /// Overlays, panels and the end-show confirmation.
        case chrome
    }

    public var scope: Scope {
        switch self {
        case .next, .playNextRequest, .previous, .skipCurrent:
            .show
        case .cycleColumns, .pageBack, .pageForward, .resetZoom, .restartScroll,
             .scrollFaster, .scrollPageDown, .scrollPageUp, .scrollSlower, .toggleAutoScroll,
             .zoomIn, .zoomOut:
            .viewport
        case .jumpToPass1, .jumpToPass2, .jumpToPass3, .jumpToPass4, .jumpToPass5,
             .jumpToPass6, .jumpToPass7, .jumpToPass8, .jumpToPass9, .toggleLoop,
             .togglePlayAlong:
            .viewport
        case .toggleBassNotes, .toggleFillTab, .toggleSingerView:
            .viewport
        case .endShow, .openSearch, .showKeys, .toggleMetronome, .toggleMetronomeClick,
             .toggleRequests, .toggleSidebar:
            .chrome
        }
    }

    /// Whether a held key (auto-repeat) may repeat this command: only continuous scroll and
    /// zoom. A repeat never changes songs, toggles, cycles, confirms or plays (R154).
    public var repeatsWhenHeld: Bool {
        switch self {
        case .scrollFaster, .scrollPageDown, .scrollPageUp, .scrollSlower, .zoomIn, .zoomOut:
            true
        default:
            false
        }
    }

    /// Commands that existed once and were removed: a current `bindings.json` naming one
    /// still loads, the binding skipped (R147 removed the collapse toggle).
    public static let retired: Set = ["toggleCollapseRepeats"]

    /// The nine jump commands, for keys 1-9.
    public static let jumps: [Self] = [
        .jumpToPass1, .jumpToPass2, .jumpToPass3, .jumpToPass4, .jumpToPass5, .jumpToPass6,
        .jumpToPass7, .jumpToPass8, .jumpToPass9,
    ]

    /// The 0-based shown pass a jump command goes to; nil for the others.
    public var jumpIndex: Int? {
        Self.jumps.firstIndex(of: self)
    }

    /// The engine action for a `.show` command; nil for the others.
    public var showAction: ShowAction? {
        switch self {
        case .next: .next
        case .previous: .previous
        case .skipCurrent: .skipCurrent
        case .playNextRequest: .playNextRequest
        default: nil
        }
    }

    /// Short name for menus, help and the bindings list.
    public var title: String {
        switch self {
        case .next: "Next Song"
        case .previous: "Previous Song"
        case .scrollPageDown: "Scroll Down a Page"
        case .scrollPageUp: "Scroll Up a Page"
        case .pageForward: "Page, Then Next Song"
        case .pageBack: "Page Back, Then Previous Song"
        case .toggleAutoScroll: "Start/Pause Auto-Scroll"
        case .scrollFaster: "Scroll Faster"
        case .scrollSlower: "Scroll Slower"
        case .restartScroll: "Back to Top"
        case .skipCurrent: "Skip Song"
        case .openSearch: "Search Library"
        case .playNextRequest: "Play Next Request"
        case .toggleRequests: "Show Requests"
        case .toggleSidebar: "Show Set Order"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .resetZoom: "Actual Size"
        case .cycleColumns: "Columns"
        case .endShow: "End Show"
        case .showKeys: "Keyboard Shortcuts"
        case .toggleMetronome: "Metronome"
        case .toggleMetronomeClick: "Metronome Click (Rehearsal)"
        case .jumpToPass1, .jumpToPass2, .jumpToPass3, .jumpToPass4, .jumpToPass5,
             .jumpToPass6, .jumpToPass7, .jumpToPass8, .jumpToPass9:
            "Jump to Section \((jumpIndex ?? 0) + 1)"
        case .toggleLoop: "Loop Section (Rehearsal)"
        case .togglePlayAlong: "Play Along (Rehearsal)"
        case .toggleBassNotes: "Bass Notes"
        case .toggleFillTab: "Fills as Tab"
        case .toggleSingerView: "Singer View"
        }
    }
}
