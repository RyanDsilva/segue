import Foundation
import Library

// R191: setlist slots and medley members remember their song's file name, so a missing
// song is still named after a relaunch.

public extension Setlist {
    /// The setlist with each song slot's and member's `fileName` set from `names` where the
    /// library knows the song; a name already saved stays when the song is not known now
    /// (it is missing: that is when the name is needed).
    func fillingFileNames(_ names: [SongID: String]) -> Self {
        guard !names.isEmpty else { return self }
        var copy = self
        for index in copy.entries.indices {
            switch copy.entries[index].kind {
            case let .song(song):
                if let name = names[song] {
                    copy.entries[index].fileName = name
                }
            case var .medley(medley):
                for member in medley.members.indices {
                    if let name = names[medley.members[member].songId] {
                        medley.members[member].fileName = name
                    }
                }
                copy.entries[index].kind = .medley(medley)
            case .break:
                break
            }
        }
        return copy
    }
}

public extension SetlistStore {
    /// The library's current file name per song (after each catalog load): loaded setlists
    /// take them in memory (written with their next save, never on open), and every save
    /// fills them (R191).
    func setSongFileNames(_ names: [SongID: String]) {
        songFileNames = names
        for (id, stored) in setlists {
            setlists[id]?.setlist = stored.setlist.fillingFileNames(names)
        }
    }
}
