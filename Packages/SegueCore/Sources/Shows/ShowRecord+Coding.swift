import Foundation
import Setlists
import Support

// On-disk coding of show records (docs/architecture/data-compatibility.md): keys this build
// does not model are kept for the next save.

public extension ShowItem {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case itemId
        case songId
        case title
        case origin
        case requestId
        case overrides
        case note
        case state
        case arrangement
        case arrangementState
        case medley
    }

    /// Identity, song, origin and state are strict (an item this build cannot place fails
    /// the record, which is then reported and left untouched); the rest is lenient, an
    /// unreadable value kept raw for the next save.
    init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder)
        itemId = try object.required(.itemId)
        songId = try object.required(.songId)
        title = object.value(.title, default: "")
        origin = try object.required(.origin)
        requestId = object.value(.requestId)
        overrides = object.value(.overrides, default: SetlistOverrides())
        note = object.value(.note)
        state = try object.required(.state)
        arrangement = object.value(.arrangement)
        arrangementState = object.value(.arrangementState)
        medley = object.value(.medley)
        unknown = object.unknown
    }

    func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(songId, forKey: .songId)
        try container.encode(title, forKey: .title)
        try container.encode(origin, forKey: .origin)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encode(overrides, forKey: .overrides)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(arrangement, forKey: .arrangement)
        try container.encodeIfPresent(arrangementState, forKey: .arrangementState)
        try container.encodeIfPresent(medley, forKey: .medley)
    }
}

public extension ShowRecord {
    /// Identity, kind, setlist, the planned entries, the items and the start are strict (a
    /// record this build cannot replay fails, and is reported and left untouched); requests
    /// and events are read one by one (an unreadable one is kept raw and written back after
    /// the others); every other field is lenient, an unreadable value kept raw.
    init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder)
        let container = object.container
        id = try object.required(.id)
        schemaVersion = object.value(.schemaVersion, default: Self.currentSchemaVersion)
        // Kept only while the file is newer than this build (R196): it is written back then.
        minReaderVersion = schemaVersion > Self.currentSchemaVersion
            ? object.value(.minReaderVersion) : nil
        kind = try object.required(.kind)
        setlistId = try object.required(.setlistId)
        setlistName = object.value(.setlistName, default: "")
        planned = try container.decodeIfPresent([SetlistEntry].self, forKey: .planned) ?? []
        items = try container.decodeIfPresent([ShowItem].self, forKey: .items) ?? []
        currentItemId = object.value(.currentItemId)
        breakId = object.value(.breakId)
        scrollPosition = object.value(.scrollPosition, default: 0)
        requests = object.elements(.requests) ?? []
        events = object.elements(.events) ?? []
        startedAt = try object.required(.startedAt)
        updatedAt = object.value(.updatedAt) ?? startedAt
        endedAt = object.value(.endedAt)
        closure = object.value(.closure)
        gig = object.value(.gig, default: GigDetails())
        reorderReview = object.value(.reorderReview)
        readOnly = nil
        unknown = object.unknown
    }

    func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(
            SchemaMigrator.minReaderVersion(
                writing: schemaVersion,
                kept: minReaderVersion,
                current: Self.currentSchemaVersion,
                currentMinimum: Self.currentMinReaderVersion,
            ),
            forKey: .minReaderVersion,
        )
        try container.encode(kind, forKey: .kind)
        try container.encode(setlistId, forKey: .setlistId)
        try container.encode(setlistName, forKey: .setlistName)
        try container.encode(planned, forKey: .planned)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(currentItemId, forKey: .currentItemId)
        try container.encodeIfPresent(breakId, forKey: .breakId)
        try container.encode(scrollPosition, forKey: .scrollPosition)
        try container.encode(unknown.appending(requests, to: "requests"), forKey: .requests)
        try container.encode(unknown.appending(events, to: "events"), forKey: .events)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encodeIfPresent(closure, forKey: .closure)
        try container.encode(gig, forKey: .gig)
        try container.encodeIfPresent(reorderReview, forKey: .reorderReview)
    }
}

public extension GigDetails {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case venue
        case date
        case notes
        case rating
    }

    init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder)
        venue = object.value(.venue)
        date = object.value(.date)
        notes = object.value(.notes)
        rating = object.value(.rating)
        unknown = object.unknown
    }

    func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(venue, forKey: .venue)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(rating, forKey: .rating)
    }
}
