// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A (core), C (dispatch).

import Foundation

/// Every argument-free live-mode action. Keyboard now, HID pedals and MIDI later (phase 6)
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
    /// The per-song "collapse repeated sections" toggle (saved to the sidecar).
    case toggleCollapseRepeats
    /// Cycles the current song's columns Auto -> 1 -> 2 -> 3 -> Auto (saved to the sidecar
    /// as `LivePrefs.columns`).
    case cycleColumns
    /// Asks for confirmation, then ends the show.
    case endShow
    /// Shows or hides the keyboard help overlay (`?`).
    case showKeys
    /// The stage metronome's pulse on or off (`M`, R90).
    case toggleMetronome
    /// The metronome's click on or off: rehearsals only, never a sound in a gig (`⇧M`, R90).
    case toggleMetronomeClick

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
             .toggleCollapseRepeats, .zoomIn, .zoomOut:
            .viewport
        case .endShow, .openSearch, .showKeys, .toggleMetronome, .toggleMetronomeClick,
             .toggleRequests, .toggleSidebar:
            .chrome
        }
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
        case .toggleCollapseRepeats: "Collapse Repeats"
        case .cycleColumns: "Columns"
        case .endShow: "End Show"
        case .showKeys: "Keyboard Shortcuts"
        case .toggleMetronome: "Metronome"
        case .toggleMetronomeClick: "Metronome Click (Rehearsal)"
        }
    }
}
