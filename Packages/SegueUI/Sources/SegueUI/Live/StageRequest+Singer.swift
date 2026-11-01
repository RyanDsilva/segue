#if os(macOS)
    import LiveLayout
    import Shows

    /// Singer view's stage request (P9-2 section 6.2): the chart request with lyrics only,
    /// the singer style and floor, the singer zoom and no notes block. The stage, the Singer
    /// Screen and P9-1's printed Lyrics part all get it through `StageRequest.make(singer:)`.
    extension StageRequest {
        static func singerRequest(_ request: LayoutRequest, settings: LiveSettings)
            -> LayoutRequest
        {
            var singer = request
            singer.view = .singer
            singer.style = .singer
            // Never below 28 pt (R178); a long song scrolls or takes columns instead.
            singer.minLyricSize = max(request.minLyricSize, LayoutStyle.singerMinimumLyricSize)
            // One singer zoom for every song, never the song's own (P9-2 6.5).
            singer.zoom = LiveSettings.clampedSingerZoom(settings.singerZoom)
            // Song and slot notes are player reminders (R178); cues stay.
            singer.notes = []
            singer.walkUps = nil
            return singer
        }
    }
#endif
