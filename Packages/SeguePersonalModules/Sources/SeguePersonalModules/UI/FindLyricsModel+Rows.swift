import Foundation
import Plugins

extension FindLyricsModel {
    // MARK: Rows

    /// Every visible row, top to bottom, through the groups (Up/Down, spec 14).
    var rows: [Row] {
        groups.flatMap { group in
            group.songs.flatMap { song -> [Row] in
                guard song.nests, expanded.contains(song.id) else { return [.song(song.id)] }
                return [.song(song.id)] + song.versions.map { .version(key(song.group, $0)) }
            }
        }
    }

    func song(_ id: String) -> Song? {
        groups.lazy.flatMap(\.songs).first { $0.id == id }
    }

    /// The candidate a row previews: a version, or a song's best version.
    func candidate(for row: Row) -> (Song, SearchCandidate)? {
        switch row {
        case let .song(id):
            return song(id).map { ($0, $0.best) }
        case let .version(key):
            for song in groups.flatMap(\.songs) {
                if let version = song.versions.first(where: { self.key(song.group, $0) == key }) {
                    return (song, version)
                }
            }
            return nil
        }
    }

    func key(_ group: SearchGroup, _ candidate: SearchCandidate) -> String {
        "\(group.rawValue)/\(candidate.id)"
    }

    func move(_ offset: Int) {
        let rows = rows.filter { row in
            guard let (_, candidate) = candidate(for: row) else { return false }
            return candidate.isPickable
        }
        guard !rows.isEmpty else { return }
        guard let selection, let index = rows.firstIndex(of: selection) else {
            selection = offset >= 0 ? rows.first : rows.last
            return
        }
        self.selection = rows[min(max(index + offset, 0), rows.count - 1)]
    }

    /// Left and Right collapse and expand a song's versions.
    func setExpanded(_ expand: Bool) {
        guard let selection else { return }
        switch selection {
        case let .song(id):
            if expand {
                expanded.insert(id)
            } else {
                expanded.remove(id)
            }
        case .version:
            if !expand, let (song, _) = candidate(for: selection) {
                expanded.remove(song.id)
                self.selection = .song(song.id)
            }
        }
    }
}
