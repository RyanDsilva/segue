import AIEval
import Testing

/// The eval's scorer on hand-made records (the spike metrics `make eval-ai` reports).
struct EvalScoreTests {
    static let gold = GoldEntry(
        labels: [["other"], ["verse"], ["chorus", "prechorus"]],
        title: [EvalScore.norm("Paper Lanterns")],
        artist: [nil],
        key: ["G"],
    )

    static func record(labels: [String], title: String?, artist: String? = nil) -> EvalRecord {
        EvalRecord(
            fixture: "E01",
            provider: "mlx",
            labels: labels,
            headed: [false, true, false],
            title: title,
            artist: artist,
            key: "G",
            calls: [],
            skipped: false,
        )
    }

    @Test
    func `labels accept any gold alternative and split headed from unheaded`() {
        let score = EvalScore(
            records: [Self.record(
                labels: ["other", "verse", "prechorus"],
                title: "paper lanterns",
            )],
            gold: ["E01": Self.gold],
        )
        #expect(score.blocksRight == 3)
        #expect(score.headedRight == 1)
        #expect(score.songsAllLabelsRight == 1)
        #expect(score.titlesRight == 1)
        #expect(score.artistsRight == 1)
        #expect(score.keysRight == 1)
    }

    @Test
    func `an invented artist and a wrong label are misses and regress against a baseline`() {
        let good = EvalScore(
            records: [Self.record(labels: ["other", "verse", "chorus"], title: "Paper Lanterns")],
            gold: ["E01": Self.gold],
        )
        let worse = EvalScore(
            records: [Self.record(
                labels: ["other", "verse", "verse"],
                title: "Paper Lanterns",
                artist: "Made Up",
            )],
            gold: ["E01": Self.gold],
        )
        #expect(worse.artistsRight == 0)
        #expect(worse.songsAllLabelsRight == 0)
        #expect(!worse.regressions(against: good).isEmpty)
        #expect(good.regressions(against: good).isEmpty)
    }
}
