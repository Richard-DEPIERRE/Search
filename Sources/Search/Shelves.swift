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

/// One line of the pinned block as the column draws it: a folder's own row,
/// or a pin (in a folder, or not). Drags among the pins are measured in these
/// lines, so they are what the rules below move through.
enum PinnedRow: Equatable, Identifiable {
    case folder(UUID)
    case pin(UUID, folder: UUID?)

    var id: UUID {
        switch self {
        case .folder(let id): return id
        case .pin(let id, _): return id
        }
    }
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

    /// Whether a page is somewhere a kept tab can go back to. about:blank,
    /// or an extension's own page, is not: ⌘W would put the tab down there
    /// and the session, which saves only web pages, would lose it. A file
    /// on this Mac can be a home for as long as the app is open; like any
    /// file tab, it isn't brought back at the next launch.
    static func canBeHome(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "file"
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

    /// How many tabs of the row are in one section.
    static func count(_ slots: [Slot], of wanted: Section) -> Int {
        slots.filter { section(of: $0) == wanted }.count
    }

    /// Whether a failed load ends a trip home. A load cancelled — most often
    /// the one the trip itself stopped by starting — says nothing about the
    /// trip; any other failure means home isn't coming.
    static func failureEndsTrip(domain: String, code: Int) -> Bool {
        !(domain == NSURLErrorDomain && code == NSURLErrorCancelled)
    }

    // MARK: - folders of pins

    /// The pins as drawn: each folder's row where its first pin is, then its
    /// pins while it is open — while it is closed, only the one you are on.
    /// A pin whose folder isn't there is drawn loose. `pins` is the pins
    /// section, already tidied (each folder's pins side by side).
    static func pinnedRows(_ pins: [Slot], folders: [Folder], active: UUID?) -> [PinnedRow] {
        let open = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.open) })
        var rows: [PinnedRow] = []
        var drawn = Set<UUID>()
        for pin in pins {
            guard let folder = pin.folder, let isOpen = open[folder] else {
                rows.append(.pin(pin.id, folder: nil))
                continue
            }
            if !drawn.contains(folder) {
                drawn.insert(folder)
                rows.append(.folder(folder))
            }
            if isOpen || pin.id == active { rows.append(.pin(pin.id, folder: folder)) }
        }
        return rows
    }

    /// A pin carried to `target` among the drawn rows, and the folder that
    /// place puts it in: between two pins of a folder, or right under an
    /// open folder's row, it joins that folder; anywhere else it is loose.
    /// Past a closed folder it goes after the folder, never into it — Move to
    /// Folder is the way into one.
    static func movePin(_ id: UUID, to target: Int, pins: [Slot], folders: [Folder], active: UUID?) -> [Slot] {
        let rows = pinnedRows(pins, folders: folders, active: active)
        let from = rows.firstIndex { row in
            if case .pin(let pin, _) = row { return pin == id }
            return false
        }
        guard let from, rows.indices.contains(target), target != from else { return pins }
        var rest = rows
        rest.remove(at: from)
        let open = Set(folders.filter(\.open).map(\.id))
        let before = target > 0 ? rest[target - 1] : nil
        let after = target < rest.count ? rest[target] : nil
        var joins: UUID?
        switch before {
        case .folder(let folder)? where open.contains(folder):
            joins = folder
        case .pin(_, let folder?)?:
            if case .pin(_, let next)? = after, next == folder { joins = folder }
        default:
            break
        }
        rest.insert(.pin(id, folder: joins), at: target)
        return expand(rest, pins: pins, folders: folders, moved: id, into: joins)
    }

    /// A folder's row carried to `target` among the drawn rows, its pins with
    /// it. It never lands inside another folder, going before it while the
    /// hand is in that folder's first half and after it past the half.
    static func moveFolder(_ id: UUID, to target: Int, pins: [Slot], folders: [Folder], active: UUID?) -> [Slot] {
        let rows = pinnedRows(pins, folders: folders, active: active)
        guard let from = rows.firstIndex(of: .folder(id)), rows.indices.contains(target), target != from else {
            return pins
        }
        var end = from + 1
        while end < rows.count, case .pin(_, let folder) = rows[end], folder == id { end += 1 }
        let block = Array(rows[from..<end])
        var rest = rows
        rest.removeSubrange(from..<end)
        var at = min(max(0, target), rest.count)
        // Inside another folder's block, where the hand is decides: in its
        // first half the carried folder goes before it, past the half after
        // it. `at` is counted without the carried block, so the answer
        // doesn't depend on where the folder is now — it can't flip back and
        // forth while the hand holds still, or once per row as it passes.
        if at < rest.count, case .pin(_, let other?) = rest[at], let start = rest.firstIndex(of: .folder(other)) {
            var end = start + 1
            while end < rest.count, case .pin(_, let folder) = rest[end], folder == other { end += 1 }
            at = (at - start) * 2 <= end - start ? start : end
        }
        rest.insert(contentsOf: block, at: at)
        return expand(rest, pins: pins, folders: folders, moved: nil, into: nil)
    }

    /// A pin put into a folder, after its last pin — or, with nil, out of the
    /// folder it is in, to just after that folder's pins. The last pin out of
    /// a folder stays where it is: there is nothing left to be after.
    static func place(_ id: UUID, into folder: UUID?, pins: [Slot]) -> [Slot] {
        guard let from = pins.firstIndex(where: { $0.id == id }) else { return pins }
        var moving = pins[from]
        guard let anchor = folder ?? moving.folder else { return pins }
        var rest = pins
        rest.remove(at: from)
        moving.folder = folder
        let at = rest.lastIndex { $0.folder == anchor }.map { $0 + 1 } ?? min(from, rest.count)
        rest.insert(moving, at: at)
        return rest
    }

    /// Drawn rows back into the pins' order. A closed folder's pins, drawn or
    /// not, stand where its row is; every other pin stands where its own row
    /// is; `moved` takes the folder its new place gave it.
    private static func expand(_ rows: [PinnedRow], pins: [Slot], folders: [Folder], moved: UUID?, into folder: UUID?) -> [Slot] {
        let closed = Set(folders.filter { !$0.open }.map(\.id))
        var order: [Slot] = []
        var placed = Set<UUID>()
        for row in rows {
            switch row {
            case .folder(let id):
                guard closed.contains(id) else { continue }
                for slot in pins where slot.folder == id && slot.id != moved && !placed.contains(slot.id) {
                    order.append(slot)
                    placed.insert(slot.id)
                }
            case .pin(let id, _):
                guard !placed.contains(id), var slot = pins.first(where: { $0.id == id }) else { continue }
                if id == moved { slot.folder = folder }
                order.append(slot)
                placed.insert(id)
            }
        }
        // Nothing drawn is missing from the rows, but a pin is never lost to a
        // drawing: anything left over keeps its place at the end.
        for slot in pins where !placed.contains(slot.id) { order.append(slot) }
        return order
    }
}
