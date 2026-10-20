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

    @State private var position = ScrollPosition(edge: .leading)
    @State private var overflow = Overflow()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the chips run past each edge of the visible row.
    private struct Overflow: Equatable {
        var offset: CGFloat = 0
        var visible: CGFloat = 0
        var content: CGFloat = 0

        var moreBefore: Bool {
            offset > 1
        }

        var moreAfter: Bool {
            offset + visible < content - 1
        }
    }

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
        .scrollPosition($position)
        .onScrollGeometryChange(for: Overflow.self) { geometry in
            Overflow(
                offset: geometry.contentOffset.x,
                visible: geometry.containerSize.width,
                content: geometry.contentSize.width,
            )
        } action: { _, new in
            overflow = new
        }
        // Chips cut off by the column fade out at that edge, and a ‹ / › button pages the
        // row there, so a clipped chip always reads as "more this way".
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: overflow.moreBefore ? 44 : 0)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: overflow.moreAfter ? 44 : 0)
            }
        }
        .overlay(alignment: .leading) {
            if overflow.moreBefore {
                pageButton(forward: false)
            }
        }
        .overlay(alignment: .trailing) {
            if overflow.moreAfter {
                pageButton(forward: true)
            }
        }
        .accessibilityIdentifier(AccessibilityID.filterChips)
    }

    /// Scrolls the row most of a width toward `forward`'s edge.
    private func pageButton(forward: Bool) -> some View {
        Button {
            let step = max(overflow.visible - 60, 60)
            let target = forward
                ? min(overflow.offset + step, overflow.content - overflow.visible)
                : max(overflow.offset - step, 0)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                position.scrollTo(x: target)
            }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.color.ink)
                .frame(width: 22, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.color.ground),
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(forward ? "More filters" : "Earlier filters")
        .accessibilityLabel(forward ? "More filters" : "Earlier filters")
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
