import Foundation

// What was open last time. A list of addresses and their names, and which one
// you were looking at — nothing else, because everything else is either on the
// page or in the history file next door.

enum Session {
    struct Entry: Codable {
        var url: String
        var title: String
        var pin: String?
        /// The name you gave the tab, when you gave it one.
        var name: String?
        /// For a kept tab: "favorites" or "pins". Absent in a session from
        /// before there were two.
        var shelf: String?
        /// For a kept tab: the page it goes back to.
        var home: String?
        /// For a pin in a folder: the folder's id.
        var folder: String?

        /// A kept tab from before there were shelves was a card at the top:
        /// a favorite now, looking exactly as it did. Anything else this
        /// build doesn't know is read the same way.
        var keptShelf: Shelf { shelf.flatMap(Shelf.init(rawValue:)) ?? .favorites }

        /// The page a kept tab goes back to. From before there was one: the
        /// page it was on, which is the page it was put down at. A home that
        /// won't read as an address falls back the same way, rather than
        /// leaving the tab with nowhere to go back to.
        var keptHome: URL? {
            guard pin != nil else { return nil }
            return home.flatMap(URL.init(string:)) ?? URL(string: url)
        }

        var folderID: UUID? {
            guard pin != nil else { return nil }
            return folder.flatMap(UUID.init(uuidString:))
        }
    }

    struct Shape: Codable {
        var tabs: [Entry]
        var active: Int
        /// This space's folders of pins. Absent from sessions without any.
        var folders: [Folder]?
    }

    /// The first space's is the session there always was; each other space
    /// keeps its own beside it.
    private static func file(_ space: UUID) -> URL {
        Store.file(space == Space.firstID ? "session.json" : "session-\(space.uuidString).json")
    }

    static func erase(space: UUID) {
        guard space != Space.firstID else { return }
        try? FileManager.default.removeItem(at: file(space))
    }

    static func read(space: UUID = Space.firstID) -> Shape {
        let file = file(space)
        guard let data = try? Data(contentsOf: file) else { return Shape(tabs: [], active: 0) }
        guard let shape = try? JSONDecoder().decode(Shape.self, from: data) else {
            // A file that's there but won't decode is not the same as no
            // file: something wrote it, and overwriting it on the next save
            // without a trace is how yesterday's tabs actually disappear.
            Store.quarantine(file)
            return Shape(tabs: [], active: 0)
        }
        return shape
    }

    /// `now` writes on the calling thread. Quitting doesn't wait for a
    /// background queue, and a session handed to one on the way out is a
    /// session that may never reach the disk.
    static func write(now: Bool = false, space: UUID = Space.firstID, _ shape: Shape) {
        let file = file(space)
        let put = {
            guard let data = try? JSONEncoder().encode(shape) else { return }
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: file, options: .atomic)
        }
        if now {
            put()
        } else {
            DispatchQueue.global(qos: .utility).async(execute: put)
        }
    }
}

extension Session.Shape {
    /// Read leniently where a hand, or a write cut short, could have left
    /// something odd: a folder that won't read is dropped, not the session
    /// with every tab in it. Written the ordinary way.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([Session.Entry].self, forKey: .tabs)
        active = try container.decode(Int.self, forKey: .active)
        folders = (try? container.decodeIfPresent([Lossy<Folder>].self, forKey: .folders))?.compactMap(\.value)
    }
}

/// One element of a list that might not read: nil in its place instead of an
/// error for the whole list.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
