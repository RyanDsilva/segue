// P3-10: accessibility identifiers of the song card (direction 2, tokens) and the R110
// essentials dot. Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    // MARK: Song card (direction 2, tokens)

    /// The card (its token strip, plus Title and Artist when expanded).
    static let songCard = "segue.songCard"
    /// A token: `segue.songCard.token.key`, `.tempo`, `.capo`, `.time`, `.artist`, `.album`.
    static func songCardToken(_ field: SongCardField) -> String {
        "segue.songCard.token.\(field.rawValue)"
    }

    /// The Title field (expanded card, or the heading being edited in place).
    static let songCardTitle = "segue.songCard.title"
    /// The Artist field (or "Add artist").
    static let songCardArtist = "segue.songCard.artist"
    /// The artist chip field (P8-8 section 9), one chip, its input, a chip's Split button and
    /// a library suggestion.
    static let songCardArtists = "segue.songCard.artists"
    static let songCardArtistChip = "segue.songCard.artistChip"
    static let songCardArtistInput = "segue.songCard.artistInput"
    static let songCardArtistSplit = "segue.songCard.artistSplit"
    static let songCardArtistSuggestion = "segue.songCard.artistSuggestion"
    /// The Movie / Album field.
    static let songCardAlbum = "segue.songCard.album"
    /// The key picker's Major / Minor switch.
    static let songCardKeyMode = "segue.songCard.keyMode"
    /// One key in the key picker (label = the key).
    static let songCardKeyOption = "segue.songCard.keyOption"
    /// The detected key on top of the key picker ("Am, from chords").
    static let songCardKeySuggestion = "segue.songCard.keySuggestion"
    /// The Tempo field.
    static let songCardTempo = "segue.songCard.tempo"
    /// Tap tempo.
    static let songCardTap = "segue.songCard.tap"
    /// The Tempo popover's Set button.
    static let songCardSet = "segue.songCard.set"
    /// A time signature choice (4/4, 3/4, 6/8).
    static let songCardTimeOption = "segue.songCard.timeOption"
    /// "Other…" time signature.
    static let songCardTimeOther = "segue.songCard.timeOther"
    /// The Other time signature field.
    static let songCardTime = "segue.songCard.time"
    /// The capo value in the Capo popover.
    static let songCardCapo = "segue.songCard.capo"
    /// "Clear" in a popover.
    static let songCardClear = "segue.songCard.clear"
    /// The "+" menu (adds Capo or Time).
    static let songCardAdd = "segue.songCard.add"
    /// The quiet missing-essentials dot on a library or builder row (R110).
    static let songEssentialsDot = "segue.song.essentialsDot"
}
