import Foundation

/// A UI string from SegueUI's String Catalog (P9-5 4.3, R179): `uiString("Start Show")`.
/// Its `LocalizationValue` parameter makes the compiler extract each literal into
/// `Localizable.xcstrings`, and the lookup names SegueUI's bundle, not the app's. Song content
/// (titles, lyrics, chords, section labels, romanized Hindi) never goes through it.
func uiString(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: #bundle)
}
