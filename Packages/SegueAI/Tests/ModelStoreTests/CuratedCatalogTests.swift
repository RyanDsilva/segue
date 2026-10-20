import ModelPort
import ModelStore
import Testing

struct CuratedCatalogTests {
    @Test
    func `the bundled catalog has one locked, verifiable curated entry (R119)`() throws {
        let catalog = ModelStore.curatedCatalog
        let model = try #require(catalog.first)
        #expect(catalog.count == 1)
        #expect(model.isVerifiable)
        #expect(model.files.allSatisfy { $0.sha256?.count == 64 })
        #expect(model.revision == "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b")
        #expect(model.status == .locked)
    }
}
