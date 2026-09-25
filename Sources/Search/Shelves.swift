import Foundation

// Where a kept tab sits, and the rules that keep the row in order: the
// favorites first, then the pins with each folder's side by side, then
// everything else. The row itself stays one flat list — selecting,
// closing, sleeping, the session and the bench all walk it as they always
// have — and these rules are what keep that list in its shape. Nothing here
// knows about pages or views, so the rules are tested on their own
// (Tests/SearchTests).

/// Which of the two kinds of kept tab: a card at the top of the column, or
/// a row under the cards. It means something only while the tab is kept.
enum Shelf: String, Codable {
    case favorites, pins
}

/// A named group of pins. It lives only as long as it holds one: made with
/// a pin in it, gone when its last pin leaves.
struct Folder: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var open: Bool
}

/// What the rules need to know about one tab.
struct Slot: Equatable {
    var id: UUID
    var kept: Bool
    var shelf: Shelf
    var folder: UUID?
}

enum Shelves {
    enum Section: Int, Comparable {
        case favorites, pins, loose
        static func < (a: Section, b: Section) -> Bool { a.rawValue < b.rawValue }
    }

    static func section(of slot: Slot) -> Section {
        guard slot.kept else { return .loose }
        return slot.shelf == .favorites ? .favorites : .pins
    }

    /// The row in its order, and the folders still holding a pin. Stable:
    /// within a section nothing changes place, so a row that was already in
    /// order comes back exactly as it went in. A hand-edited file, or one
    /// cut short, comes back whole rather than as a column that no longer
    /// adds up.
    static func tidy(_ slots: [Slot], folders: [Folder]) -> (slots: [Slot], folders: [Folder]) {
        let known = Set(folders.map(\.id))
        let fixed = slots.map { slot -> Slot in
            var slot = slot
            if let folder = slot.folder, section(of: slot) != .pins || !known.contains(folder) {
                slot.folder = nil
            }
            return slot
        }
        let favorites = fixed.filter { section(of: $0) == .favorites }
        let loose = fixed.filter { section(of: $0) == .loose }
        let allPins = fixed.filter { section(of: $0) == .pins }
        // Each folder's pins together, where the first of them was.
        var pins: [Slot] = []
        var gathered = Set<UUID>()
        for slot in allPins {
            guard let folder = slot.folder else {
                pins.append(slot)
                continue
            }
            guard !gathered.contains(folder) else { continue }
            gathered.insert(folder)
            pins += allPins.filter { $0.folder == folder }
        }
        return (favorites + pins + loose, folders.filter { gathered.contains($0.id) })
    }

    /// A drag moves a tab among its own kind only: a favorite among the
    /// favorites, a pin among the pins, a tab among the tabs.
    static func canMove(_ slots: [Slot], from: Int, to: Int) -> Bool {
        guard slots.indices.contains(from), slots.indices.contains(to) else { return false }
        return section(of: slots[from]) == section(of: slots[to])
    }

    /// An address as far as "is this still the same page?" cares: no
    /// fragment, which a page changes as you scroll or as its app moves
    /// about; no trailing slash; the scheme and the host in lower case.
    static func normalised(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        parts.fragment = nil
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if parts.path.hasSuffix("/") { parts.path.removeLast() }
        return parts.string ?? url.absoluteString
    }

    /// Whether a kept tab is on its own page. Where the last trip home
    /// landed counts — a site that sends its front door on to an inbox
    /// hasn't taken you anywhere. With no address, or no home, there is
    /// nowhere to be away from.
    static func isHome(_ address: URL?, home: URL?, landed: URL?) -> Bool {
        guard let address, let home else { return true }
        let here = normalised(address)
        if here == normalised(home) { return true }
        if let landed, here == normalised(landed) { return true }
        return false
    }

    /// Where the session saves a tab. A kept tab that is awake on its own
    /// page is saved at its home, not at wherever the trip home landed: the
    /// landing isn't saved, so a relaunch would find it on a page that is
    /// neither and count it as away. Asleep, it is saved where it was put
    /// down; away, where it wandered to — both are what the next launch
    /// should open.
    static func savedAddress(address: URL, home: URL?, kept: Bool, asleep: Bool, away: Bool) -> URL {
        guard kept, !asleep, !away, let home else { return address }
        return home
    }
}
