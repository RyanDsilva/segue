import Foundation
import Services
import Testing

/// The closed analytics vocabulary (spec 14.2-4): every rendered name, key and value obeys
/// the section 5 patterns, and no event can carry a string.
struct ServicesVocabularyTests {
    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.wholeMatch(of: try! Regex(pattern)) != nil // swiftlint:disable:this force_try
    }

    @Test
    func `every signal name, key and value is in the allowed shape`() {
        let sample = VocabularySample.all
        var names: Set<String> = []
        for event in sample {
            let signal = event.render()
            names.insert(signal.name)
            #expect(
                Self.matches(signal.name, #"Segue\.[A-Z][A-Za-z]+\.[a-z][A-Za-z]+"#),
                "\(signal.name)",
            )
            #expect(!signal.params.isEmpty)
            for (key, value) in signal.params {
                #expect(Self.matches(key, #"segue\.[a-z][A-Za-z0-9]+"#), "\(key)")
                #expect(Self.matches(value, #"[A-Za-z0-9+<>._-]{1,24}"#), "\(key)=\(value)")
            }
            let crumb = Breadcrumb(event)
            #expect(crumb.category == "segue")
            #expect(crumb.message == signal.name)
            #expect(crumb.data == signal.params)
        }
        // Rows 1-18 of section 5, the phase 3 AI rows 19-22, the section notes row 23
        // (P3-17), one signal name each, the set composer row 24 (P8-5), two signals, the
        // walk-up row 25 (P8-4b), the fill row 26, the timing rows 27 and 28 (P8-7), the
        // artist split row 29 and the setlist time row 30 (P8-8), the PDF export row 31
        // (P9-1), the medley row 32 (P9-3).
        #expect(names.count == 33)
        #expect(names.isSuperset(of: [
            "Segue.AI.pasteFinished", "Segue.AI.modelDownload", "Segue.AI.assistantUsed",
            "Segue.AI.smartFilterUsed", "Segue.Notes.edited", "Segue.Setlist.composed",
            "Segue.Setlist.composerSession", "Segue.Bass.walkUpPicked",
            "Segue.Bass.fillSaved", "Segue.Timing.tapCaptured", "Segue.Timing.keyChange",
            "Segue.Song.artistSplit", "Segue.Setlist.timed", "Segue.Export.pdf",
            "Segue.Setlist.medley",
        ]))
    }

    /// Rows 24 and 21 (P8-8 section 8): the composer's artist qualifier and the request's
    /// artist and Movie / Album chips, as Bools.
    @Test
    func `the composer and assistant carry the artist Bools`() {
        let composed = AnalyticsEvent.setlistComposed(ComposerSummary(
            action: .song,
            tier: .artist,
            form: .original,
            alternative: false,
            key: false,
            entry: .click,
            artistWords: true,
        )).render()
        #expect(composed.params["segue.tier"] == "artist")
        #expect(composed.params["segue.artistWords"] == "true")
        let used = AnalyticsEvent.aiAssistantUsed(AssistantUsedSummary(
            context: .builder,
            lexiconChips: SmallBucket(2),
            suggestedShown: SmallBucket(0),
            suggestedAccepted: SmallBucket(0),
            provider: .noProvider,
            rebuilt: false,
            artistChips: true,
            albumChips: false,
        )).render()
        #expect(used.params["segue.artistChips"] == "true")
        #expect(used.params["segue.albumChips"] == "false")
    }

    /// Row 29 (P8-8): the separator from a split's separators, daily per (source,
    /// separator, outcome).
    @Test
    func `the artist split row`() {
        #expect(ArtistSplitSeparator(separators: ["comma"]) == .comma)
        #expect(ArtistSplitSeparator(separators: ["feat", "ampersand"]) == .mixed)
        #expect(ArtistSplitSeparator(separators: []) == nil)
        #expect(ArtistSplitSeparator(separators: ["mixed"]) == nil)
        let event = AnalyticsEvent.songArtistSplit(ArtistSplitSummary(
            source: .paste,
            parts: SmallBucket(2),
            separator: .ampersand,
            outcome: .merged,
        ))
        #expect(event.render().name == "Segue.Song.artistSplit")
        #expect(event.render().params == [
            "segue.source": "paste", "segue.parts": "2-4", "segue.separator": "ampersand",
            "segue.outcome": "merged",
        ])
        #expect(event.throttle == .daily(key: "Segue.Song.artistSplit|paste|ampersand|merged"))
        #expect(ComposerTier(rawValue: "artist") == .artist)
        #expect(FeatureKey(rawValue: "songArtists") == .songArtists)
    }

    /// Row 32 and the medley params of rows 24 and 30 (P9-3 section 14): enums and buckets,
    /// daily per (action, entry).
    @Test
    func `the medley row and the medley params`() {
        let event = AnalyticsEvent.setlistMedley(
            action: .transitionEdited,
            members: SmallBucket(3),
            entry: .key,
        )
        #expect(event.render().name == "Segue.Setlist.medley")
        #expect(event.render().params == [
            "segue.action": "transitionEdited", "segue.members": "2-4", "segue.entry": "key",
        ])
        #expect(event.throttle == .daily(key: "Segue.Setlist.medley|transitionEdited|key"))
        let composed = AnalyticsEvent.setlistComposed(ComposerSummary(
            action: .medley,
            tier: .exactTitle,
            form: .original,
            alternative: false,
            key: true,
            entry: .click,
            members: SmallBucket(3),
        )).render()
        #expect(composed.params["segue.action"] == "medley")
        #expect(composed.params["segue.members"] == "2-4")
        let song = AnalyticsEvent.setlistComposed(ComposerSummary(
            action: .song,
            tier: .exactTitle,
            form: .original,
            alternative: false,
            key: false,
            entry: .click,
        )).render()
        #expect(song.params["segue.members"] == nil)
        let timed = AnalyticsEvent.setlistTimed(SetlistTimedSummary(
            songs: SmallBucket(5),
            noTempo: SmallBucket(0),
            noChords: SmallBucket(0),
            arranged: SmallBucket(0),
            estimatedOnly: false,
            target: .noTarget,
            medleys: SmallBucket(1),
            medleyUnknown: true,
        )).render()
        #expect(timed.params["segue.medleys"] == "1")
        #expect(timed.params["segue.medleyUnknown"] == "true")
        #expect(FeatureKey(rawValue: "medley") == .medley)
    }

    /// Row 30 and the P8-8 time params (section 8): buckets and Bools only; Time it is gone.
    @Test
    func `the setlist time row and the no-time params`() {
        let event = AnalyticsEvent.setlistTimed(SetlistTimedSummary(
            songs: SmallBucket(12),
            noTempo: SmallBucket(2),
            noChords: SmallBucket(0),
            arranged: SmallBucket(1),
            estimatedOnly: true,
            target: .within,
        ))
        #expect(event.render().name == "Segue.Setlist.timed")
        #expect(event.render().params == [
            "segue.songs": "10-19", "segue.noTempo": "2-4", "segue.noChords": "0",
            "segue.arranged": "1", "segue.estimatedOnly": "true", "segue.target": "within",
            "segue.medleys": "0", "segue.medleyUnknown": "false",
        ])
        #expect(event.throttle == .daily(key: "Segue.Setlist.timed|within"))
        #expect(FeatureKey(rawValue: "timeIt") == nil)
        #expect(FeatureKey(rawValue: "tempoFromSet") == .tempoFromSet)
        let assistant = AnalyticsEvent.aiAssistantUsed(AssistantUsedSummary(
            context: .builder,
            lexiconChips: SmallBucket(1),
            suggestedShown: SmallBucket(0),
            suggestedAccepted: SmallBucket(0),
            provider: .noProvider,
            rebuilt: false,
            leftOut: SmallBucket(3),
        ))
        #expect(assistant.render().params["segue.leftOut"] == "2-4")
        let snapshot = AnalyticsEvent.librarySnapshot(LibrarySnapshot(
            songs: SongBucket(40),
            setlists: SmallBucket(1),
            gigs: SmallBucket(0),
            welcomeSongsLeft: .noneLeft,
            customShapes: false,
            noTempo: SongBucket(5),
        ))
        #expect(snapshot.render().params["segue.noTempo"] == SongBucket(5).rawValue)
    }

    @Test
    func `no event can hold a string`() {
        func strings(in value: Any, path: String) -> [String] {
            switch value {
            case is Character, is Data, is String, is Substring, is URL:
                return [path]
            default:
                return Mirror(reflecting: value).children.flatMap { child in
                    strings(in: child.value, path: path + "." + (child.label ?? "_"))
                }
            }
        }
        for event in VocabularySample.all {
            #expect(strings(in: event, path: "\(event)").isEmpty)
        }
    }

    @Test
    func `bucket boundaries`() {
        #expect([0, 1, 9, 10, 49, 50, 99, 100, 249, 250, 499, 500, 999, 1000, 50000].map {
            SongBucket($0).rawValue
        } == [
            "0", "1-9", "1-9", "10-49", "10-49", "50-99", "50-99", "100-249", "100-249",
            "250-499", "250-499", "500-999", "500-999", "1000+", "1000+",
        ])
        #expect([-1, 0, 1, 2, 4, 5, 9, 10, 19, 20, 49, 50].map { SmallBucket($0).rawValue } == [
            "0", "0", "1", "2-4", "2-4", "5-9", "5-9", "10-19", "10-19", "20-49", "20-49", "50+",
        ])
        #expect([0, 899, 900, 1799, 1800, 3599, 3600, 5399, 5400, 7199, 7200].map {
            DurationBucket(seconds: TimeInterval($0)).rawValue
        } == [
            "<15m", "<15m", "15-30m", "15-30m", "30-60m", "30-60m", "60-90m", "60-90m",
            "90-120m", "90-120m", "120m+",
        ])
        #expect([0, 1, 2, 6, 7, 13, 14, 29, 30, 89, 90].map { DaysBucket(days: $0).rawValue } == [
            "0", "1", "2-6", "2-6", "7-13", "7-13", "14-29", "14-29", "30-89", "30-89", "90+",
        ])
        #expect([nil, 0, 0.99, 1, 2.9, 3, 9.9, 10, 29.9, 30].map {
            LatencyBucket(seconds: $0).rawValue
        } == ["none", "<1s", "<1s", "1-3s", "1-3s", "3-10s", "3-10s", "10-30s", "10-30s", "30s+"])
        #expect([0, 1, 2, 3, 4, 40].map { CorrectionBucket(changes: $0).rawValue } == [
            "none", "small", "medium", "medium", "large", "large",
        ])
        #expect([0, 59, 60, 299, 300, 899, 900, 3599, 3600].map {
            DownloadDurationBucket(seconds: TimeInterval($0)).rawValue
        } == ["<1m", "<1m", "1-5m", "1-5m", "5-15m", "5-15m", "15-60m", "15-60m", "60m+"])
    }

    /// P9-2 section 13: singer view's feature key and contexts, and the show-ended Bool.
    @Test
    func `singer view is a feature with a screen context and a show-ended Bool`() {
        let used = AnalyticsEvent.featureUsed(.singerView, .screen).render()
        #expect(used.params["segue.feature"] == "singerView")
        #expect(used.params["segue.context"] == "screen")
        let ended = AnalyticsEvent.showEnded(ShowSummary(
            kind: .rehearsal,
            duration: .under15m,
            played: .zero,
            skipped: .zero,
            requestsUsed: false,
            autoScrollUsed: false,
            reordered: false,
            endedBy: .endShow,
            singerView: true,
        )).render()
        #expect(ended.params["segue.singer"] == "true")
        let stage = AnalyticsEvent.featureUsed(.singerView, .stage).throttle
        #expect(stage != AnalyticsEvent.featureUsed(.singerView, .library).throttle)
    }

    /// Row 31 (P9-1 spec 11, R181): the PDF export summary's keys and the render time
    /// buckets; Help's PDF item and the export error code.
    @Test
    func `the PDF export summary renders its closed values`() {
        let signal = AnalyticsEvent.pdfExported(PDFExportSummary(
            target: .selection,
            part: .bass,
            paper: .letter,
            size: .large,
            columns: .two,
            repeats: .compact,
            fitOnePage: false,
            sectionMap: true,
            stageNotes: false,
            diagrams: .noDiagrams,
            fills: .tab,
            saved: true,
            printed: false,
            shared: true,
            songs: SmallBucket(12),
            pages: SmallBucket(30),
            medleys: SmallBucket(0),
            optionChanges: SmallBucket(2),
            renderTime: RenderTimeBucket(.milliseconds(700)),
        )).render()
        #expect(signal.name == "Segue.Export.pdf")
        #expect(signal.params["segue.target"] == "selection")
        #expect(signal.params["segue.diagrams"] == "none")
        #expect(signal.params["segue.fills"] == "tab")
        #expect(signal.params["segue.renderTime"] == "under1s")
        #expect(signal.params.count == 19)
        #expect(RenderTimeBucket(.milliseconds(120)) == .under250ms)
        #expect(RenderTimeBucket(.seconds(3)) == .over2s)
        #expect(AnalyticsEvent.helpOpened(.pdf).render().params["segue.item"] == "pdf")
        #expect(AnalyticsEvent.errorOccurred(.pdfExport).render()
            .params["segue.code"] == "pdfExport")
    }

    /// P9-5 section 6: row 14's route and origin, sent only when known.
    @Test func `help opened carries its route and origin only when known`() {
        let menu = AnalyticsEvent.helpOpened(.help, via: .book).render()
        #expect(menu.name == "Segue.Help.opened")
        #expect(menu.params == ["segue.item": "help", "segue.via": "book"])
        let button = AnalyticsEvent.helpOpened(.contextHelp, via: .web).render()
        #expect(button.params == ["segue.item": "contextHelp", "segue.via": "web"])
        let report = AnalyticsEvent.helpOpened(.reportProblem, from: .errorBanner).render()
        #expect(report.params == ["segue.item": "reportProblem", "segue.from": "errorBanner"])
        #expect(AnalyticsEvent.helpOpened(.terms).render().params == ["segue.item": "terms"])
        #expect(AnalyticsEvent.featureUsed(.songDragOut, .library).render()
            .params["segue.feature"] == "songDragOut")
    }
}
