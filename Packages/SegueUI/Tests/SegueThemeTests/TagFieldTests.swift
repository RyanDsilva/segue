@testable import SegueUI
import Testing

/// The song card's tag field completions (P3-6, R71): library tags by prefix, and the six
/// starter tags only while the library has no tags of the user's own.
struct TagFieldTests {
    @Test
    func `an empty library offers the six starter tags on an empty field`() {
        let offered = TagEditor.completions(
            draft: "",
            applied: [],
            libraryTags: [],
            seedTags: ["Welcome"],
        )
        #expect(offered == ["upbeat", "ballad", "crowd pleaser", "singalong", "original", "cover"])
    }

    @Test
    func `the Welcome tag does not count as the user's own`() {
        let offered = TagEditor.completions(
            draft: "c",
            applied: ["cover"],
            libraryTags: ["Welcome"],
            seedTags: ["Welcome"],
        )
        #expect(offered == ["crowd pleaser"])
    }

    @Test
    func `own tags replace the starters and complete by prefix`() {
        let library = ["Gig opener", "ghazal", "upbeat"]
        #expect(TagEditor.completions(
            draft: "",
            applied: [],
            libraryTags: library,
            seedTags: ["Welcome"],
        )
        .isEmpty)
        #expect(TagEditor.completions(
            draft: "G",
            applied: ["ghazal"],
            libraryTags: library,
            seedTags: [],
        )
            == ["Gig opener"])
        #expect(TagEditor.completions(draft: "b", applied: [], libraryTags: library, seedTags: [])
            .isEmpty) // "ballad" is a starter only, gone once the user has tags
    }

    @Test
    func `the bundled Welcome manifest supplies the seed tag`() {
        #expect(TagEditor.seedTags == ["Welcome"])
    }
}
