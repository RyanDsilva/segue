#if os(macOS)
    import Foundation
    import Library
    import Support
    import SwiftUI

    /// Tags as removable chips plus an "Add tag" field (Return adds; existing tags are
    /// offered as completions). Case-insensitive duplicates are ignored. While the library
    /// has no tags of its own (the Welcome songs' tag does not count), the field offers the
    /// six starter tags instead (R71): a manual pick only, nothing is applied for the user.
    struct TagEditor: View {
        let tags: [String]
        let suggestions: [String]
        var isDisabled = false
        let onChange: ([String]) -> Void
        @State private var draft = ""

        var body: some View {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                        Button {
                            onChange(tags.filter { $0 != tag })
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.color.muted)
                                .frame(width: 14, height: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isDisabled)
                        .accessibilityLabel(uiString("Remove \(tag)"))
                        .accessibilityIdentifier(AccessibilityID.songTagRemove)
                    }
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.ink)
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.vertical, 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(tag)
                    .accessibilityIdentifier(AccessibilityID.songTag)
                }
                TextField(uiString("Add tag"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .frame(width: 120)
                    .padding(.vertical, 4)
                    .textInputSuggestions {
                        ForEach(completions, id: \.self) { tag in
                            Text(tag).textInputCompletion(tag)
                        }
                    }
                    .onSubmit(add)
                    .disabled(isDisabled)
                    .accessibilityLabel(uiString("Add tag"))
                    .accessibilityIdentifier(AccessibilityID.songTagField)
            }
        }

        private var completions: [String] {
            Self.completions(
                draft: draft,
                applied: tags,
                libraryTags: suggestions,
                seedTags: Self.seedTags,
            )
        }

        /// Up to six tags to offer for `draft`: the library's tags it prefixes, and while the
        /// library has no tags of the user's own, the starter tags (all of them while the
        /// field is empty). Tags already `applied` are left out; matching ignores case.
        nonisolated static func completions(
            draft: String,
            applied: [String],
            libraryTags: [String],
            seedTags: [String],
        ) -> [String] {
            let typed = draft.trimmingCharacters(in: .whitespaces).lowercased()
            let starters = StarterTags.suggestions(libraryTags: libraryTags, seedTags: seedTags)
            guard !typed.isEmpty || !starters.isEmpty else { return [] }
            var result: [String] = []
            for tag in starters + libraryTags {
                let isNew = !(applied + result).contains {
                    $0.caseInsensitiveCompare(tag) == .orderedSame
                }
                if isNew, typed.isEmpty || tag.lowercased().hasPrefix(typed) {
                    result.append(tag)
                }
            }
            return Array(result.prefix(6))
        }

        /// The tag the bundled Welcome songs carry (not the user's own), from its manifest.
        nonisolated static let seedTags: [String] = {
            guard let folder = Bundle.module.url(forResource: "WelcomeLibrary", withExtension: nil),
                  let manifest = try? SeedManifest.load(
                      fromFolder: folder,
                      fileSystem: LiveFileSystem(),
                  )
            else { return [] }
            return [manifest.tag]
        }()

        private func add() {
            let tag = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            draft = ""
            guard !tag.isEmpty,
                  !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
            else { return }
            onChange(tags + [tag])
        }
    }
#endif
