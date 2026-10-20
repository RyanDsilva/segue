#if os(macOS)
    import Library
    import SwiftUI

    /// The quiet dot on a library row or the builder's library column when the song lacks
    /// a set essential (R110). Its help and VoiceOver name what is missing; nothing when
    /// the song has all three.
    struct SongEssentialsMark: View {
        let record: SongRecord

        var body: some View {
            let missing = record.missingEssentials
            if !missing.isEmpty {
                EssentialsDot()
                    .padding(4)
                    .contentShape(Rectangle())
                    .help("\(SetEssential.spokenMissing(missing)). \(SetEssential.help)")
                    .accessibilityHidden(false)
                    .accessibilityElement()
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityLabel(SetEssential.spokenMissing(missing))
                    .accessibilityIdentifier(AccessibilityID.songEssentialsDot)
            }
        }
    }
#endif
