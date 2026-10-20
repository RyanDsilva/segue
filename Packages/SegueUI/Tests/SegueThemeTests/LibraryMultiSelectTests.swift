@testable import SegueUI
import Testing

/// Library multi-select (R84, P3-12 step 4): Finder's click, ⌘-click, ⇧-click and ⇧↑/⇧↓
/// rules on `ListSelection`, the selection model `SelectableList` drives.
struct LibraryMultiSelectTests {
    private let rows = ["a", "b", "c", "d", "e"]

    @Test
    func `a click selects one row and ⌘-click toggles others in and out`() {
        var selection = ListSelection<String>()
        selection.select("b")
        selection.toggle("d", in: rows)
        selection.toggle("a", in: rows)

        #expect(selection.ordered(in: rows) == ["a", "b", "d"])
        #expect(selection.focus == "a")
        #expect(selection.isMultiple)

        // Removing the focused row moves the focus to the nearest selected row after it.
        selection.toggle("a", in: rows)
        #expect(selection.ordered(in: rows) == ["b", "d"])
        #expect(selection.focus == "b")

        selection.select("e")
        #expect(selection.ordered(in: rows) == ["e"])
        #expect(!selection.isMultiple)
    }

    @Test
    func `shift-click selects the range from the anchor either way`() {
        var selection = ListSelection(single: "b")
        selection.extend(to: "d", in: rows)
        #expect(selection.ordered(in: rows) == ["b", "c", "d"])
        #expect(selection.focus == "d")

        // The anchor stays at b: a second ⇧-click above it flips the range.
        selection.extend(to: "a", in: rows)
        #expect(selection.ordered(in: rows) == ["a", "b"])
        #expect(selection.anchor == "b")
    }

    @Test
    func `shift-arrows grow and shrink the range, plain arrows collapse it`() {
        var selection = ListSelection(single: "c")
        selection.move(1, in: rows, extending: true)
        selection.move(1, in: rows, extending: true)
        #expect(selection.ordered(in: rows) == ["c", "d", "e"])
        selection.move(1, in: rows, extending: true) // clamped at the last row
        #expect(selection.ordered(in: rows) == ["c", "d", "e"])
        selection.move(-1, in: rows, extending: true)
        #expect(selection.ordered(in: rows) == ["c", "d"])

        selection.move(-1, in: rows, extending: false)
        #expect(selection.ordered(in: rows) == ["c"])
        #expect(selection.focus == "c")

        var empty = ListSelection<String>()
        empty.move(-1, in: rows, extending: true)
        #expect(empty.ordered(in: rows) == ["e"])
    }

    @Test
    func `rows that leave the list leave the selection`() {
        var selection = ListSelection(single: "a")
        selection.toggle("c", in: rows)
        selection.toggle("e", in: rows)

        selection.keep(only: ["b", "c", "d"])

        #expect(selection.ordered(in: rows) == ["c"])
        #expect(selection.focus == "c")
        #expect(selection.anchor == "c")
    }
}
