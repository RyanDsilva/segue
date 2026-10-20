// Phase 3 (P3-6): accessibility identifiers of the Smart Filters sidebar section, the
// filter editor sheet and the tag management sheets. Mirror new IDs in the UITests target
// when an E2E test uses them (it cannot import SegueUI).

public extension AccessibilityID {
    // MARK: Sidebar

    /// The "Smart Filters" section header.
    static let sidebarSmartFilters = "segue.sidebar.smartFilters"
    /// A saved smart filter's row.
    static let sidebarSmartFilter = "segue.sidebar.smartFilter"
    /// The built-in "Missing essentials" row (R110).
    static let missingEssentialsRow = "segue.sidebar.missingEssentials"
    /// "New Smart Filter" in the section.
    static let newSmartFilter = "segue.sidebar.newSmartFilter"

    // MARK: Editor sheet

    static let smartFilterName = "segue.smartFilter.name"
    static let smartFilterConditions = "segue.smartFilter.conditions"
    static let smartFilterRow = "segue.smartFilter.row"
    static let smartFilterField = "segue.smartFilter.field"
    static let smartFilterOperator = "segue.smartFilter.operator"
    static let smartFilterAddRow = "segue.smartFilter.addRow"
    static let smartFilterRemoveRow = "segue.smartFilter.removeRow"
    static let smartFilterAddKey = "segue.smartFilter.addKey"
    static let smartFilterLower = "segue.smartFilter.lower"
    static let smartFilterUpper = "segue.smartFilter.upper"
    static let smartFilterMatchCount = "segue.smartFilter.matchCount"
    static let smartFilterSave = "segue.smartFilter.save"
    /// The list header naming the filter ("Openers, 7 songs, Edit...").
    static let smartFilterListHeader = "segue.smartFilter.listHeader"
    static let smartFilterEdit = "segue.smartFilter.edit"

    // MARK: Tag sheets

    static let tagNameField = "segue.tag.nameField"
    static let tagMergeTarget = "segue.tag.mergeTarget"
    static let tagSheetCommit = "segue.tag.commit"
}
