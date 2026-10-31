import Library

/// The lane's shift-click span as a fill span (P8-7 section 12.1): the lane is the only way
/// to include grid chords and `{chorus}` stub chords.
extension PlayAlong {
    /// The span as indices into the song's written-order timeline (the lane shows a slice
    /// of it); nil without a span.
    var fillSpan: ClosedRange<Int>? {
        guard let span, source != nil,
              let low = songIndex(span.lowerBound), let high = songIndex(span.upperBound),
              low < high
        else { return nil }
        return low ... high
    }

    /// Why the lane span cannot take a fill.
    var fillSpanProblem: FillSpanProblem? {
        guard let source, let fillSpan else { return nil }
        return FillSpan.problem(timeline: source.timeline, chords: fillSpan)
    }

    /// The written-order index of the lane's chord `index`.
    private func songIndex(_ index: Int) -> Int? {
        let slice = timeline.timeline.chords
        guard let source, slice.indices.contains(index) else { return nil }
        let chord = slice[index]
        let pass = chord.pass + timeline.passes.lowerBound
        return source.timeline.chords.firstIndex { other in
            other.pass == pass && other.position == chord.position
                && other.occurrence == chord.occurrence && other.isSilent == chord.isSilent
        }
    }
}
