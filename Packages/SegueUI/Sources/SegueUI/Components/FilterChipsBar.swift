import Library
import SwiftUI

/// The chip row under a song search field: the three proficiency levels, then the library's
/// most used tags. Typed tokens ("ready, upbeat, key G") filter the same way; chips are the
/// clickable form. Simple filtering only (phase 2); nothing is saved.
struct FilterChipsBar: View {
    @Binding var state: SongFilterState
    /// The library's tags, most used first.
    let tags: [TagCount]
    var maxTags = 8

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Proficiency.allCases, id: \.self) { level in
                    let isOn = state.proficiencies.contains(level)
                    FilterChip(isOn: isOn) {
                        state.toggle(level)
                    } label: {
                        HStack(spacing: 6) {
                            ProficiencyDot(level, inverted: isOn)
                            Text(ProficiencyMark.label(level))
                        }
                    }
                    .accessibilityLabel(ProficiencyMark.label(level))
                    .accessibilityIdentifier(AccessibilityID.filterProficiency(level))
                    .help("Show only \(ProficiencyMark.label(level)) songs")
                }
                if !shownTags.isEmpty {
                    Rule(axis: .vertical)
                        .frame(height: 16)
                        .padding(.horizontal, 4)
                }
                ForEach(shownTags, id: \.self) { tag in
                    FilterChip(tag, isOn: state.hasTag(tag)) { state.toggleTag(tag) }
                        .accessibilityIdentifier(AccessibilityID.filterTag)
                        .help("Show only songs tagged “\(tag)”")
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
        // Fade the trailing edge so chips cut off by the column read as scrollable.
        .mask {
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
            }
        }
        .accessibilityIdentifier(AccessibilityID.filterChips)
    }

    /// The most used tags, plus any tag chip that is on but no longer among them.
    private var shownTags: [String] {
        var shown = tags.prefix(maxTags).map(\.tag)
        for tag in state.tags.sorted() where !shown.contains(where: {
            $0.caseInsensitiveCompare(tag) == .orderedSame
        }) {
            shown.append(tag)
        }
        return shown
    }
}
