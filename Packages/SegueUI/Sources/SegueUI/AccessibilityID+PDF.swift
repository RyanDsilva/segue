// P9-1: accessibility identifiers of the PDF export and its preview sheet. Mirror new IDs in
// the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// The preview sheet (spec 6.2).
    static let pdfSheet = "segue.pdf.sheet"
    /// "Songbook PDF · 18 songs · 31 pages" under the title.
    static let pdfSubtitle = "segue.pdf.subtitle"
    /// The pages (`PDFView`) and the page indicator under them.
    static let pdfView = "segue.pdf.view"
    static let pdfPageIndicator = "segue.pdf.pageIndicator"
    /// "Making the PDF..." and the error banner's Try Again.
    static let pdfProgress = "segue.pdf.progress"
    static let pdfError = "segue.pdf.error"
    static let pdfTryAgain = "segue.pdf.tryAgain"
    static let pdfShare = "segue.pdf.share"
    static let pdfSave = "segue.pdf.save"
    static let pdfPrint = "segue.pdf.print"
    static let pdfDone = "segue.pdf.done"
    /// An option: `part`, `paper`, `size`, `columns`, `fitOnePage`, `repeats`, `sectionMap`,
    /// `diagrams`, `fillsAsTab`, `stageNotes`.
    static func pdfOption(_ name: String) -> String {
        "segue.pdf.option.\(name)"
    }

    /// The entry points: the song row's and the slot row's context menu items, the setlist
    /// menu's Export PDF... and Print..., and the selection's "Export N Songs as PDF...".
    static let pdfExportSong = "segue.pdf.export.song"
    static let pdfExportSlot = "segue.pdf.export.slot"
    static let pdfExportSetlist = "segue.pdf.export.setlist"
    static let pdfPrintSetlist = "segue.pdf.print.setlist"
    static let pdfExportSelection = "segue.pdf.export.selection"
}
