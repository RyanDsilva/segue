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
        // Rows 1-18 of section 5 plus the phase 3 AI rows 19-22, one signal name each.
        #expect(names.count == 22)
        #expect(names.isSuperset(of: [
            "Segue.AI.pasteFinished", "Segue.AI.modelDownload", "Segue.AI.assistantUsed",
            "Segue.AI.smartFilterUsed",
        ]))
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
}
