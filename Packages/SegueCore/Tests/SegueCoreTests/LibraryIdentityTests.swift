import Foundation
import Support
import Testing

/// `.segue/library.json` (P9-6 5.1) on a real temp folder.
struct LibraryIdentityTests {
    @Test
    func `the ID is minted once and read back on every later open`() throws {
        let lib = try TestLibrary()
        let first = try LibraryIdentity.resolve(
            root: lib.root,
            fileSystem: lib.fileSystem,
            clock: lib.clock,
            ids: lib.ids,
        )
        lib.clock.advance(by: 60)
        let again = try LibraryIdentity.resolve(
            root: lib.root,
            fileSystem: lib.fileSystem,
            clock: lib.clock,
            ids: lib.ids,
        )

        #expect(again == first)
        #expect(try lib.read(".segue/library.json") == """
        {
          "createdAt" : "2026-01-01T00:00:00.000Z",
          "id" : "\(first.id)",
          "schema" : 1
        }

        """)
    }

    @Test
    func `an unreadable file goes to the Trash and the folder gets a new ID`() throws {
        let lib = try TestLibrary()
        try lib.write("not json", to: ".segue/library.json")

        let identity = try LibraryIdentity.resolve(
            root: lib.root,
            fileSystem: lib.fileSystem,
            clock: lib.clock,
            ids: lib.ids,
        )

        #expect(lib.trashedNames() == ["library.json"])
        #expect(LibraryIdentity.read(root: lib.root, fileSystem: lib.fileSystem)
            == .valid(identity))
    }

    @Test
    func `a newer schema with an ID is kept and never rewritten`() throws {
        let lib = try TestLibrary()
        let id = "01JBZ6S0X5Q4M3N2P1R0S9T8V7"
        let newer = #"{"schema": 2, "id": "\#(id)", "createdAt": "2026-10-01T10:00:00Z", "#
            + #""zone": "x"}"#
        try lib.write(newer, to: ".segue/library.json")

        let identity = try LibraryIdentity.resolve(
            root: lib.root,
            fileSystem: lib.fileSystem,
            clock: lib.clock,
            ids: lib.ids,
        )

        #expect(identity.id.description == id)
        #expect(identity.schema == 2)
        #expect(try lib.read(".segue/library.json") == newer)
        #expect(lib.trashedNames().isEmpty)
    }
}
