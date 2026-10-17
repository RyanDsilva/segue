#if os(macOS)
    import AppKit

    /// AppKit versions of the theme tokens for the TextKit 2 editors. Colours are the asset
    /// catalog's dynamic colours, so they resolve per appearance at draw time (light editor,
    /// dark appearance) exactly like `Theme.color`.
    @MainActor
    enum EditorStyle {
        // MARK: Colours (docs/brand.md section 5)

        static let cueText = token("cueText", fallback: .systemRed)
        static let ink = token("ink", fallback: .labelColor)
        static let ground = token("ground", fallback: .textBackgroundColor)
        static let muted = token("muted", fallback: .secondaryLabelColor)
        static let line = token("line", fallback: .separatorColor)
        static let lineStrong = token("lineStrong", fallback: .tertiaryLabelColor)
        static let surfaceAlt = token("surfaceAlt", fallback: .controlBackgroundColor)

        /// Line numbers: `muted`, lighter (the mockup's #8E8E96 on paper).
        static let lineNumber = muted.withAlphaComponent(0.7)
        /// The source pane ground: half `surfaceAlt` over paper (#FAFAFB in the mockup).
        static let sourceGround = surfaceAlt.withAlphaComponent(0.5)
        /// Inline diagnostics (error / warning underline).
        static let errorUnderline = NSColor.systemRed
        static let warningUnderline = NSColor.systemOrange

        private static func token(_ name: String, fallback: NSColor) -> NSColor {
            NSColor(named: name, bundle: Theme.bundle) ?? fallback
        }

        // MARK: Fonts (docs/brand.md section 6)

        static func grotesk(_ face: SchibstedGrotesk, size: CGFloat) -> NSFont {
            _ = FontRegistration.registerBundledFonts()
            return NSFont(name: face.rawValue, size: size)
                ?? .systemFont(ofSize: size, weight: face.systemWeight)
        }

        /// ChordPro source: 14pt monospaced (mockup E2 a).
        static let sourceFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        static let sourceChordFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        static let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        /// Source line height (mockup: 14px at line-height 1.75).
        static let sourceLineHeight: CGFloat = 24
        /// Raises source glyphs so they sit centred in the 24pt line (TextKit puts the extra
        /// line height above the glyphs).
        static let sourceBaselineOffset: CGFloat = 3.5

        /// Visual canvas lyric: 24 / 400, line height 1.25 (mockup E2 b).
        static let canvasLyricSize: CGFloat = 24
        static var canvasLyricFont: NSFont {
            grotesk(.regular, size: canvasLyricSize)
        }

        /// Chord pill text: 16 / 700.
        static var pillFont: NSFont {
            grotesk(.bold, size: 16)
        }

        /// Section label: 13 / 700.
        static var labelFont: NSFont {
            grotesk(.bold, size: 13)
        }

        static var commentFont: NSFont {
            grotesk(.medium, size: 15)
        }

        static let verbatimFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    }

    extension SchibstedGrotesk {
        var systemWeight: NSFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semiBold: .semibold
            case .bold: .bold
            case .extraBold: .heavy
            }
        }
    }

    /// Scroll view settings shared by both editor views.
    @MainActor
    enum EditorScrollView {
        static func configure(_ scrollView: NSScrollView) {
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false
            scrollView.contentView.drawsBackground = false
        }
    }

    /// Text view settings shared by both editor modes: every automatic text transformation
    /// off, so what is typed is what is saved. Lyrics are often romanized Hindi, which macOS
    /// would otherwise "correct" into English (phase 1 spec, "Text input settings for
    /// lyrics"; decisions.md, Language: "Editor input").
    @MainActor
    enum EditorTextInput {
        static func configure(_ textView: NSTextView) {
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsUndo = true
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isGrammarCheckingEnabled = false
            textView.isAutomaticTextCompletionEnabled = false
            textView.isAutomaticLinkDetectionEnabled = false
            textView.isAutomaticDataDetectionEnabled = false
            textView.smartInsertDeleteEnabled = false
            textView.usesInspectorBar = false
            textView.usesFontPanel = false
            textView.allowsDocumentBackgroundColorChange = false
            // No text checking at all: automatic capitalization and double-space period run
            // as part of it, following the system setting unless the view opts out.
            textView.enabledTextCheckingTypes = 0
            textView.inlinePredictionType = .no
            textView.mathExpressionCompletionType = .no
            textView.writingToolsBehavior = .none
        }

        /// The settings above as one string, exposed to UI tests (they cannot read
        /// NSTextView properties out of process). Every flag must read "off".
        static func report(_ textView: NSTextView) -> String {
            let flags: [(String, Bool)] = [
                ("spelling", textView.isAutomaticSpellingCorrectionEnabled),
                ("continuousSpelling", textView.isContinuousSpellCheckingEnabled),
                ("grammar", textView.isGrammarCheckingEnabled),
                ("replacement", textView.isAutomaticTextReplacementEnabled),
                ("quotes", textView.isAutomaticQuoteSubstitutionEnabled),
                ("dashes", textView.isAutomaticDashSubstitutionEnabled),
                ("completion", textView.isAutomaticTextCompletionEnabled),
                ("capitalization", Self.capitalizes(textView)),
                ("prediction", textView.inlinePredictionType != .no),
            ]
            return flags.map { "\($0.0)=\($0.1 ? "on" : "off")" }.joined(separator: " ")
        }

        /// Automatic capitalization is not an NSTextView property: it comes from the system
        /// setting via NSSpellChecker, and only applies when text checking runs. It is off
        /// when the text view has no automatic text checking that could capitalize.
        static func capitalizes(_ textView: NSTextView) -> Bool {
            textView.enabledTextCheckingTypes != 0
                || textView.isAutomaticSpellingCorrectionEnabled
                || textView.isAutomaticTextReplacementEnabled
        }
    }
#endif
