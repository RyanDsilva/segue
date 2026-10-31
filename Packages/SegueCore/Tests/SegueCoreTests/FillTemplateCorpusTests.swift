import Foundation
import Library
import MusicTheory
import Testing

/// The templates are grounded in the fill corpus (P8-7 section 11.4 item 2): every template
/// cites real examples, every corpus family has a template (or a stated reason not to), and
/// the corpus stays inside the closed vocabularies.
struct FillTemplateCorpusTests {
    static let corpus = FillCorpus.shared

    @Test
    func `the corpus fixture loads at schema 1 with 81 examples`() throws {
        let corpus = try #require(Self.corpus)
        #expect(corpus.schema == 1)
        #expect(corpus.ticksPerQuarter * FillCorpus.scale == 480)
        #expect(corpus.examples.count == 81)
    }

    @Test
    func `every template cites corpus examples of its own family`() throws {
        let corpus = try #require(Self.corpus)
        let byID = Dictionary(uniqueKeysWithValues: corpus.examples.map { ($0.id, $0) })
        for template in FillTemplates.standard.templates {
            #expect(!template.corpus.isEmpty, "\(template.id) cites nothing")
            for id in template.corpus {
                let example = try #require(byID[id], "\(template.id) cites unknown \(id)")
                let family = example.family
                let expected = FillTemplates.untemplated[family] ?? family
                #expect(
                    expected == template.corpusFamily || family == template.corpusFamily,
                    "\(template.id) cites \(id) of family \(family)",
                )
            }
        }
    }

    @Test
    func `every corpus family has a template or a stated reason`() throws {
        let corpus = try #require(Self.corpus)
        let implemented = Set(FillTemplates.standard.templates.map(\.corpusFamily))
        for family in Set(corpus.examples.map(\.family)) {
            #expect(
                implemented.contains(family) || FillTemplates.untemplated[family] != nil,
                "no template for corpus family \(family)",
            )
        }
        // Every family the corpus declares is one its examples use, and vice versa.
        #expect(Set(corpus.families) == Set(corpus.examples.map(\.family)))
    }

    @Test
    func `the prior table counts the corpus`() throws {
        let corpus = try #require(Self.corpus)
        var counts: [String: [BassGenre: Int]] = [:]
        for example in corpus.examples {
            let genre = try #require(example.generatorGenre, "\(example.id)")
            counts[example.family, default: [:]][genre, default: 0] += 1
        }
        #expect(counts == FillTemplates.standard.counts)
    }

    static let tokens: Set = [
        "R", "b2", "2", "b3", "3", "4", "#4", "b5", "5", "#5", "b6", "6", "b7", "7", "8", "b9",
        "9", "T", "T:5", "T:3", "S", "C", "CT", "X", "M",
    ]

    @Test
    func `the corpus stays inside the closed vocabularies`() throws {
        let corpus = try #require(Self.corpus)
        let articulations = Set(Articulation.allCases.map(\.rawValue))
        for example in corpus.examples {
            for event in example.events {
                let token = event.note
                let known = Self.tokens.contains(token)
                    || token.wholeMatch(of: /T[+-][1-4]/) != nil
                    || token.wholeMatch(of: /NK:[1-7]/) != nil
                #expect(known, "\(example.id): unknown note token \(token)")
                for articulation in event.art ?? [] {
                    // `doubleStop` is checked as pitches only (generatorScope partial).
                    #expect(
                        articulations.contains(articulation)
                            || articulation == "doubleStop" && example.checks
                            .generatorScope == "partial",
                        "\(example.id): unknown articulation \(articulation)",
                    )
                }
            }
            #expect(example.generatorGenre != nil, "\(example.id): unknown feel")
        }
    }

    @Test
    func `templates use the spec's closed function vocabulary`() {
        let letters = Set(FillFunction.allCases.map(\.rawValue))
        #expect(letters == ["R", "C", "S", "A", "O", "P", "D"])
        for template in FillTemplates.standard.templates {
            #expect(template.slots.allSatisfy { letters.contains($0.pitch.function.rawValue) })
            #expect(template.coversSpan || !template.slots.isEmpty, "\(template.id)")
        }
        #expect(Set(FillTemplates.standard.templates.map(\.id)).count
            == FillTemplates.standard.templates.count)
    }
}
