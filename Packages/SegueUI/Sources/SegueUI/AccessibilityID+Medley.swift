/// P9-3 6.5: the medley row in the setlist builder.
public extension AccessibilityID {
    /// A medley's header (a container: title, "3 songs", key path, time, lock, chevron).
    static let medley = "segue.setlist.medley"
    /// The header's title (double-click or Return on the header renames it).
    static let medleyTitle = "segue.setlist.medley.title"
    /// The header's "3 songs".
    static let medleySongCount = "segue.setlist.medley.songs"
    /// The header's key path "G → A → D".
    static let medleyKeyPath = "segue.setlist.medley.keyPath"
    /// The disclosure chevron.
    static let medleyDisclosure = "segue.setlist.medley.disclosure"
    /// A member row ("4b").
    static let medleyMember = "segue.setlist.medley.member"
    /// A transition row's field ("Transition into Tum Hi Ho").
    static let medleyTransition = "segue.setlist.medley.transition"
    /// A transition row's change line ("G → A · capo 2 → no capo").
    static let medleyChanges = "segue.setlist.medley.changes"
    /// The collapsed medley's member chips.
    static let medleyChips = "segue.setlist.medley.chips"
    /// A reprise mark ("also 8", "reprise of 4a").
    static let medleyReprise = "segue.setlist.medley.reprise"
}
