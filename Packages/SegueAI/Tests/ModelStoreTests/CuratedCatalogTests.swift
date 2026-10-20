import ModelPort
import ModelStore
import Testing

struct CuratedCatalogTests {
    @Test
    func `the bundled catalog has one verifiable curated entry`() throws {
        let catalog = ModelStore.curatedCatalog
        let model = try #require(catalog.first)
        #expect(catalog.count == 1)
        #expect(model.isVerifiable)
        #expect(model.files.allSatisfy { $0.sha256?.count == 64 })
        #expect(model.revision.count == 40)
    }
}
