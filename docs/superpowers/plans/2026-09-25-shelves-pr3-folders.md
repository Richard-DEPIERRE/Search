# Shelves PR 3 — folders among the pins — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one level of folders among the pins, as in Arc:
- a folder row with a chevron, which opens and closes;
- the folder's pins indented under it, hidden while it's closed (except the tab you're on);
- dragging pins into and out of open folders, and dragging a whole folder;
- renaming a folder in place, and deleting it.

It also clears the follow-ups that PRs 1 and 2 left for part 3.

**Architecture:** PR 1 already stores a tab's `folder` and each space's `folders`. This PR adds the folder rules to the pure `Shelves.swift`:
- `PinnedRow` is one drawn line of the pinned block, either a folder's row or a pin;
- `pinnedRows` turns the pins into those lines;
- `movePin` and `moveFolder` turn a drag over the drawn lines back into the pins' order and folders;
- `place` puts a pin into a folder, or takes it out.

`Browser` applies their results to the flat `tabs` list and tidies. The sidebar draws `browser.pinnedRows` with the existing `SideRow`, a new `FolderRow`, and the existing `Carried` drag.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftPM, AppKit + SwiftUI + WebKit, Swift Testing, and `./bench`.

**Spec:** `docs/superpowers/specs/2026-09-25-sidebar-favorites-pins-folders-design.md`. This plan is **PR 3** of §5. It is stacked:
- branch `sidebar-folders`, cut from `sidebar-pins` (PR 2, Richard-DEPIERRE/Search#2);
- its PR's base is `sidebar-pins`.

**Where this departs from the spec (pending the owner's say):**
1. **No spring-loading.** The spec's "hold a pin over a folder row for about 0.5 s and let go to add it to the end; a closed folder opens" is replaced by a **Move to Folder ▸** submenu on a pin, which lists the other folders. The reason: `Carried` moves rows live as you drag, so a dragged pin never rests over a folder row, and spring-loading would need a separate drag system. Dragging into *open* folders works exactly as the spec says.
2. **A short wait on a folder row.** A folder row answers a single click (open or close) after a double-click has had its chance, so opening a folder waits a moment before responding. Double-click renames it.

## Global Constraints

- macOS 14 or later. No dependencies beyond what Apple ships. Swift language mode v5 for every target.
- **One level of folders.** A folder holds pins, never other folders. Folders exist only among the pins. A folder exists only while it holds a pin: it's made with one, and it goes when its last pin leaves.
- **Order invariant:** `[favorites…] [pins…, each folder's pins next to each other] [today's tabs…]`, kept by `Browser.tidyTabs()`.
- **Rows:** folder rows and pin rows are both 28pt (`SideBar.row`), with `SideBar.gap` (2pt) between them. Pins inside a folder are indented by `SideBar.indent`, which is 14pt.
- **Drag rules** (spec §2):
  - a pin dropped between two pins of a folder, or directly under an **open** folder's row, joins that folder;
  - dropped above a folder's row, or below its last pin, it leaves;
  - dragging a folder's row moves the whole folder;
  - a folder never lands inside another.
- **Closed folders:** a closed folder hides its pins, except the tab you're on, which stays visible under its row.
- **Menus** (spec §2 menu table):
  - a pin gets New Folder with This Pin, Remove from Folder (when it's in one), plus the added Move to Folder ▸;
  - a folder row gets Rename Folder and Delete Folder. Deleting a folder leaves its pins as loose pins, in place.
- **The top tab bar** shows no folders: favorites and pins stay squares, in order.
- **Pure rules:** `Shelves.swift` imports Foundation only. Every new rule in it gets a test.
- **Voice:** comments are plain sentences explaining *why*. No attribution lines in commits or PR bodies. Never run `./ideas`.
- **Changelog:** one line under `## Unreleased` › `### Added`.
- **Testing safety:** checks drive only the test instance (`.build/debug/Search`, `./bench --test`). Never touch `~/Library/Application Support/Search/`.

## Review Focus

1. **A dragged pin landing next to a folder.** Where it lands decides whether it's in the folder: above the folder row it leaves, directly under an open folder's row it joins, and just past a closed folder it goes after the folder, not into it. Pinned by `MovePinTests` in Task 1 and the drag steps in Task 5.
2. **Dragging a folder next to another folder.** It never goes inside the other one. Pinned by `MoveFolderTests` (the two tests that check it jumps past or before the other folder) in Task 1, and by Task 5, Step 5.
3. **A session with a broken folder entry**, whether hand-edited or half-written. The tabs survive, and only the broken folder is dropped. Pinned by `SessionTests` in Task 2 and the seeded relaunch in Task 5, Step 7.
4. **The tab you're on inside a closed folder** stays visible under the folder's row, and stops showing once you leave it. Pinned by `PinnedRowsTests` in Task 1.
5. **`rowsEnd` with folder rows.** The window's drag area starts where the drawn rows stop. Pinned by the `hit` scan in Task 5, Step 8.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/Search/Shelves.swift` | Modify | `PinnedRow`, `pinnedRows`, `movePin`, `moveFolder` and `place`, plus the private `expand`. |
| `Tests/SearchTests/ShelvesTests.swift` | Modify | `PinnedRowsTests`, `MovePinTests`, `MoveFolderTests` and `PlaceTests`. |
| `Sources/Search/Session.swift` | Modify | `Shape` decodes `folders` leniently. |
| `Tests/SearchTests/SessionTests.swift` | Modify | Two tests for lenient folders. |
| `Sources/Search/Browser.swift` | Modify | The folder API: `editingFolder`, `pinnedRows`, `newFolder`, `putInFolder`, `beginFolderRename`, `renameFolder`, `endFolderEdit`, `toggleFolder`, `deleteFolder`, `movePinRow` and `moveFolderRow`. Also: `writeSession` saves only folders in use, `tripInterrupted` only fires for navigations that replace the page, `editLetter` only works on favorites, and `slots(of:)` becomes internal. |
| `Sources/Search/Spaces.swift` | Modify | `enter` ends a folder rename. |
| `Sources/Search/TabBar.swift` | Modify | The current space's `Parked` carries its folders; `KeptTabCommands` gets the pin folder items. |
| `Sources/Search/Side.swift` | Modify | `SideBar.indent`; `pinRows` draws `pinnedRows`; `pinBlock`; the space preview; new `FolderRow` and `FolderField`. |
| `Sources/Search/Bench.swift` | Modify | The `folder` verb; add `folder` to the command list. |
| `bench` | Modify | The client and output for `folder`. |
| `CHANGELOG.md` | Modify | One "Added" line. |

---

### Task 1: The folder rules, tested

**Files:**
- Modify: `Sources/Search/Shelves.swift`. Add `PinnedRow` after `struct Slot`, and new functions before the closing brace of `enum Shelves`.
- Modify: `Tests/SearchTests/ShelvesTests.swift`, by appending new suites.

**Interfaces:**
- Consumes (PR 1/2): `Slot { id, kept, shelf, folder }`, `Folder { id, name, open }`, `Shelves.section(of:)`.
- Produces (used by Tasks 3–5):
  - `enum PinnedRow: Equatable, Identifiable { case folder(UUID); case pin(UUID, folder: UUID?) }`. Its `id` is the folder's or the pin's id.
  - `static func Shelves.pinnedRows(_ pins: [Slot], folders: [Folder], active: UUID?) -> [PinnedRow]`
  - `static func Shelves.movePin(_ id: UUID, to target: Int, pins: [Slot], folders: [Folder], active: UUID?) -> [Slot]`
  - `static func Shelves.moveFolder(_ id: UUID, to target: Int, pins: [Slot], folders: [Folder], active: UUID?) -> [Slot]`
  - `static func Shelves.place(_ id: UUID, into folder: UUID?, pins: [Slot]) -> [Slot]`
  - `pins` is the pins section only, in order. `target` is the new index among the drawn rows (`Carried`'s index). Each function returns the pins section in its new order, with each slot's `folder` set.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SearchTests/ShelvesTests.swift`. The file already defines `slot(_:kept:_:folder:)`, `work` (open) and `play` (closed).

```swift
// Six pins: 1 and 2 in Work (open), 3 loose, 4 and 5 in Play (closed), 6 loose.
private let pinsFixture: [Slot] = [
    slot(1, kept: true, .pins, folder: work.id),
    slot(2, kept: true, .pins, folder: work.id),
    slot(3, kept: true, .pins),
    slot(4, kept: true, .pins, folder: play.id),
    slot(5, kept: true, .pins, folder: play.id),
    slot(6, kept: true, .pins),
]
private let bothFolders = [work, play]
private let side = Folder(id: UUID(uuidString: "F0000000-0000-0000-0000-000000000003")!, name: "Side", open: true)

private func pinID(_ n: Int) -> UUID { slot(n).id }
private func numbers(_ pins: [Slot]) -> [Int] { pins.map { Int($0.id.uuidString.suffix(12))! } }
private func folder(of n: Int, in pins: [Slot]) -> UUID? { pins.first { $0.id == pinID(n) }?.folder }

@Suite struct PinnedRowsTests {
    @Test func foldersShowTheirRowAndOpenOnesTheirPins() {
        let rows = Shelves.pinnedRows(pinsFixture, folders: bothFolders, active: nil)
        #expect(rows == [
            .folder(work.id), .pin(pinID(1), folder: work.id), .pin(pinID(2), folder: work.id),
            .pin(pinID(3), folder: nil), .folder(play.id), .pin(pinID(6), folder: nil),
        ])
    }

    @Test func theTabYouAreOnShowsUnderItsClosedFolder() {
        let rows = Shelves.pinnedRows(pinsFixture, folders: bothFolders, active: pinID(5))
        #expect(rows == [
            .folder(work.id), .pin(pinID(1), folder: work.id), .pin(pinID(2), folder: work.id),
            .pin(pinID(3), folder: nil), .folder(play.id), .pin(pinID(5), folder: play.id), .pin(pinID(6), folder: nil),
        ])
    }

    @Test func aPinInAFolderThatIsNotThereIsDrawnLoose() {
        let ghost = UUID()
        let rows = Shelves.pinnedRows([slot(7, kept: true, .pins, folder: ghost)], folders: [], active: nil)
        #expect(rows == [.pin(pinID(7), folder: nil)])
    }
}

@Suite struct MovePinTests {
    // Rows as drawn: 0 Work, 1 p1, 2 p2, 3 p3, 4 Play (closed), 5 p6.

    @Test func betweenTwoPinsOfAFolderJoinsIt() {
        let out = Shelves.movePin(pinID(3), to: 2, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 3, 2, 4, 5, 6])
        #expect(folder(of: 3, in: out) == work.id)
    }

    @Test func directlyUnderAnOpenFoldersRowJoinsIt() {
        let out = Shelves.movePin(pinID(3), to: 1, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [3, 1, 2, 4, 5, 6])
        #expect(folder(of: 3, in: out) == work.id)
    }

    @Test func belowAFoldersLastPinLeavesIt() {
        let out = Shelves.movePin(pinID(2), to: 3, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 3, 2, 4, 5, 6])
        #expect(folder(of: 2, in: out) == nil)
    }

    @Test func aboveAFoldersRowLeavesIt() {
        let out = Shelves.movePin(pinID(1), to: 0, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 2, 3, 4, 5, 6])
        #expect(folder(of: 1, in: out) == nil)
    }

    @Test func aboveAClosedFolderStaysOut() {
        let out = Shelves.movePin(pinID(6), to: 4, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 2, 3, 6, 4, 5])
        #expect(folder(of: 6, in: out) == nil)
    }

    @Test func pastAClosedFolderGoesAfterItNotIntoIt() {
        let out = Shelves.movePin(pinID(3), to: 4, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 2, 4, 5, 3, 6])
        #expect(folder(of: 3, in: out) == nil)
    }

    @Test func theTabYouAreOnLeavesItsClosedFolder() {
        // Rows: 0 Work, 1 p1, 2 p2, 3 p3, 4 Play, 5 p5 (shown: you are on it), 6 p6.
        let out = Shelves.movePin(pinID(5), to: 4, pins: pinsFixture, folders: bothFolders, active: pinID(5))
        #expect(numbers(out) == [1, 2, 3, 5, 4, 6])
        #expect(folder(of: 5, in: out) == nil)
    }

    @Test func nowhereOrTheSamePlaceChangesNothing() {
        #expect(Shelves.movePin(pinID(3), to: 9, pins: pinsFixture, folders: bothFolders, active: nil) == pinsFixture)
        #expect(Shelves.movePin(pinID(3), to: 3, pins: pinsFixture, folders: bothFolders, active: nil) == pinsFixture)
    }
}

@Suite struct MoveFolderTests {
    @Test func aClosedFolderMovedUpTakesItsPins() {
        let out = Shelves.moveFolder(play.id, to: 3, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 2, 4, 5, 3, 6])
    }

    @Test func movedUpIntoAnotherFolderItLandsBeforeIt() {
        let out = Shelves.moveFolder(play.id, to: 2, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [4, 5, 1, 2, 3, 6])
    }

    @Test func anOpenFolderMovedDownPassesOneRow() {
        let out = Shelves.moveFolder(work.id, to: 1, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [3, 1, 2, 4, 5, 6])
    }

    @Test func movedDownPastAClosedFolderItGoesAfterIt() {
        let out = Shelves.moveFolder(work.id, to: 2, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [3, 4, 5, 1, 2, 6])
    }

    @Test func movedDownIntoAnotherFolderItLandsAfterIt() {
        // Rows: 0 Side, 1 p1, 2 p2, 3 Work, 4 p3, 5 p4.
        let pins = [
            slot(1, kept: true, .pins, folder: side.id),
            slot(2, kept: true, .pins),
            slot(3, kept: true, .pins, folder: work.id),
            slot(4, kept: true, .pins, folder: work.id),
        ]
        let out = Shelves.moveFolder(side.id, to: 2, pins: pins, folders: [side, work], active: nil)
        #expect(numbers(out) == [2, 3, 4, 1])
    }
}

@Suite struct PlaceTests {
    @Test func intoAFolderGoesToItsEnd() {
        let out = Shelves.place(pinID(3), into: work.id, pins: pinsFixture)
        #expect(numbers(out) == [1, 2, 3, 4, 5, 6])
        #expect(folder(of: 3, in: out) == work.id)
    }

    @Test func intoAClosedFolderGoesToItsEnd() {
        let out = Shelves.place(pinID(6), into: play.id, pins: pinsFixture)
        #expect(numbers(out) == [1, 2, 3, 4, 5, 6])
        #expect(folder(of: 6, in: out) == play.id)
    }

    @Test func outOfAFolderGoesJustAfterIt() {
        let out = Shelves.place(pinID(1), into: nil, pins: pinsFixture)
        #expect(numbers(out) == [2, 1, 3, 4, 5, 6])
        #expect(folder(of: 1, in: out) == nil)
    }

    @Test func theLastPinOutOfAFolderStaysWhereItIs() {
        let pins = [slot(1, kept: true, .pins, folder: work.id), slot(2, kept: true, .pins)]
        let out = Shelves.place(pinID(1), into: nil, pins: pins)
        #expect(numbers(out) == [1, 2])
        #expect(folder(of: 1, in: out) == nil)
    }

    @Test func outOfNoFolderChangesNothing() {
        #expect(Shelves.place(pinID(3), into: nil, pins: pinsFixture) == pinsFixture)
    }
}
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `swift test 2>&1 | tail -20`
Expected: a compile failure, `cannot find 'PinnedRow' in scope` / `type 'Shelves' has no member 'pinnedRows'`.

- [ ] **Step 3: `PinnedRow`**

In `Sources/Search/Shelves.swift`, directly after the closing brace of `struct Slot`, add:

```swift

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
```

- [ ] **Step 4: The rules**

In `Sources/Search/Shelves.swift`, directly before the closing brace of `enum Shelves` (after `failureEndsTrip`), add:

```swift

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
    /// it. It never lands inside another folder: carried down it goes past
    /// the other folder's pins, carried up it goes before that folder's row.
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
        if at < rest.count, case .pin(_, let other?) = rest[at] {
            if target > from {
                while at < rest.count, case .pin(_, let folder) = rest[at], folder == other { at += 1 }
            } else if let row = rest.firstIndex(of: .folder(other)) {
                at = row
            }
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
```

- [ ] **Step 5: Run the tests and check they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `✔ Test run with 56 tests in 13 suites passed`. That is 35 before, plus 3 + 8 + 5 + 5 new tests, in 4 new suites.

- [ ] **Step 6: Commit**

```bash
git add Sources/Search/Shelves.swift Tests/SearchTests/ShelvesTests.swift
git commit -m "The rules for folders of pins: how they are drawn, and where a drag or a menu puts a pin or a folder"
```

---

### Task 2: Follow-ups from parts 1 and 2

**Files:**
- Modify: `Sources/Search/Session.swift`. Add an extension after `enum Session`.
- Modify: `Tests/SearchTests/SessionTests.swift`
- Modify: `Sources/Search/Browser.swift`:
  - `writeSession`'s `folders:` argument;
  - the `tripInterrupted` line in `decidePolicyFor action:`, and the scheme list in the same function;
  - `editLetter`;
  - `private static func slots(of`.
- Modify: `Sources/Search/TabBar.swift`, at about line 195: `Parked(tabs: browser.tabs, active: browser.activeID)`.

**Interfaces:**
- Consumes: `Session.Shape`, `Folder`.
- Produces:
  - `Session.Shape` decodes a `folders` array leniently.
  - `Browser.slots(of:)` becomes `static func` without `private`. Task 4's preview uses it.
  - `static let Browser.pageSchemes: [String]`

- [ ] **Step 1: Write the failing tests**

Append inside `@Suite struct SessionTests { … }` in `Tests/SearchTests/SessionTests.swift`, before its closing brace:

```swift

    @Test func aFolderThatWontReadIsDroppedNotTheSession() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A","pin":"A","shelf":"pins","folder":"F0000000-0000-0000-0000-000000000001"}],
         "active":0,
         "folders":[{"id":"F0000000-0000-0000-0000-000000000001","name":"Work","open":true},{"name":"no id"}]}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.tabs.count == 1)
        #expect(shape.folders?.map(\.name) == ["Work"])
    }

    @Test func foldersThatAreNotAListAreDroppedNotTheSession() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A"}],"active":0,"folders":"nonsense"}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.tabs.count == 1)
        #expect(shape.folders == nil)
    }
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `swift test 2>&1 | tail -20`
Expected: both new tests FAIL with a decoding error. Today a bad folder throws, and the whole `Shape` fails to decode.

- [ ] **Step 3: Lenient folders**

At the end of `Sources/Search/Session.swift`, after the closing brace of `enum Session`, add:

```swift

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
```

Being in an extension keeps `Shape`'s memberwise initializer. `CodingKeys` is still synthesized for encoding, and it can be used from this file. If the compiler says `CodingKeys` can't be reached, add `enum CodingKeys: String, CodingKey { case tabs, active, folders }` inside `struct Shape`.

- [ ] **Step 4: Run the tests and check they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `✔ Test run with 58 tests in 13 suites passed`.

- [ ] **Step 5: The session writes only folders in use**

In `Browser.swift`'s `writeSession`, replace:

```swift
                folders: folders.isEmpty ? nil : folders
```

with:

```swift
                // Only folders a pin is in: one emptied by a tab that left some
                // way other than through tidying isn't written out.
                folders: {
                    let used = Set(tabs.compactMap { $0.pin != nil && $0.shelf == .pins ? $0.folder : nil })
                    let kept = folders.filter { used.contains($0.id) }
                    return kept.isEmpty ? nil : kept
                }()
```

- [ ] **Step 6: Only a navigation that replaces the page ends a trip home**

In `Browser.swift`, find the scheme list in `decidePolicyFor action:`:

```swift
        if ["http", "https", "file", "about", "data", "blob", "chrome-extension", "webkit-extension"].contains(scheme) {
```

Replace it with:

```swift
        if Browser.pageSchemes.contains(scheme) {
```

Directly above `func tab(for webView: WKWebView) -> Tab?`, add:

```swift
    /// What a page can load in place. chrome-extension: an extension's own
    /// pages — options, a side panel, a tab it opened. WebKit serves them;
    /// nothing else here does. Anything else is handed to another app.
    static let pageSchemes = ["http", "https", "file", "about", "data", "blob", "chrome-extension", "webkit-extension"]
```

Then replace the trip line in the main-frame block, `if action.navigationType != .other { tab.tripInterrupted() }`, with:

```swift
            if action.navigationType != .other, action.targetFrame != nil, Browser.pageSchemes.contains(scheme) {
                tab.tripInterrupted()
            }
```

Update the comment just above it so it says the navigation must also replace this page: not a new window, and not a link handed to another app.

- [ ] **Step 7: Letters are the favorites'**

In `Browser.swift`, change `func editLetter(_ tab: Tab)`'s guard from `guard tab.pin != nil else { return }` to:

```swift
        // A pin is a row with its title; only a favorite wears a letter. The
        // top bar draws both as squares, and a double-click there is for this.
        guard tab.pin != nil, tab.shelf == .favorites else { return }
```

- [ ] **Step 8: `slots(of:)` for the preview, and the current space's folders in the top bar's preview**

In `Browser.swift`, change `private static func slots(of row: [Tab]) -> [Slot]` to `static func slots(of row: [Tab]) -> [Slot]`.

In `TabBar.swift`, change `? Parked(tabs: browser.tabs, active: browser.activeID)` to:

```swift
                ? Parked(tabs: browser.tabs, active: browser.activeID, folders: browser.folders)
```

- [ ] **Step 9: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then `✔ Test run with 58 tests in 13 suites passed`.

- [ ] **Step 10: Commit**

```bash
git add Sources/Search/Session.swift Tests/SearchTests/SessionTests.swift Sources/Search/Browser.swift Sources/Search/TabBar.swift
git commit -m "A folder that won't read no longer costs the session, and a few loose ends from pins are tied"
```

---

### Task 3: The browser's folders, and their menus

**Files:**
- Modify: `Sources/Search/Browser.swift`. Add a new block directly after `setHome(_:)`.
- Modify: `Sources/Search/Spaces.swift`: `enter(_:)`, next to `cancelTabEdit()`.
- Modify: `Sources/Search/TabBar.swift`: the pins branch of `KeptTabCommands.body`.

**Interfaces:**
- Consumes:
  - `Shelves.pinnedRows`, `movePin`, `moveFolder` and `place` (Task 1);
  - `Browser.slots(of:)`, `tidyTabs()`, `favoriteCount`, `pinCount`, `writeSession(now:)`, `rememberSession()`, `folders`.
- Produces (used by Tasks 4–5), on `Browser`:
  - `@Published var editingFolder: UUID?`
  - `var pinnedRows: [PinnedRow]`
  - `func newFolder(with tab: Tab)`, which names the folder "New Folder" and starts renaming it
  - `func putInFolder(_ tab: Tab, _ folder: UUID?)`
  - `func beginFolderRename(_ id: UUID)`, `func renameFolder(_ id: UUID, to typed: String)`, `func endFolderEdit()`
  - `func toggleFolder(_ id: UUID)`, `func deleteFolder(_ id: UUID)`
  - `func movePinRow(_ tab: Tab, to row: Int)`, `func moveFolderRow(_ id: UUID, to row: Int)`

- [ ] **Step 1: The folder API**

In `Browser.swift`, directly after the closing brace of `func setHome(_ tab: Tab)`, add:

```swift

    // MARK: - folders of pins

    /// The folder whose name is being typed over, in place.
    @Published var editingFolder: UUID?

    /// The pins section of the row, as the shelf rules see it.
    private var pinSlots: [Slot] {
        Browser.slots(of: tabs).filter { Shelves.section(of: $0) == .pins }
    }

    /// The pins as the column draws them: each folder's row, then its pins
    /// while it is open (see Shelves.pinnedRows).
    var pinnedRows: [PinnedRow] {
        Shelves.pinnedRows(pinSlots, folders: folders, active: activeID)
    }

    /// A folder made around a pin, open, and named at once.
    func newFolder(with tab: Tab) {
        guard tab.pin != nil, tab.shelf == .pins else { return }
        let folder = Folder(id: UUID(), name: "New Folder", open: true)
        objectWillChange.send()
        folders.append(folder)
        tab.folder = folder.id
        tidyTabs()
        editingFolder = folder.id
        writeSession(now: true)
    }

    /// Into a folder, after its last pin — or, with nil, out of the one it is
    /// in, to just after it (see Shelves.place). Into a closed one, it opens,
    /// so the pin doesn't vanish from under the menu that sent it there.
    func putInFolder(_ tab: Tab, _ folder: UUID?) {
        guard tab.pin != nil, tab.shelf == .pins else { return }
        if let folder, let i = folders.firstIndex(where: { $0.id == folder }), !folders[i].open {
            folders[i].open = true
        }
        reorderPins(Shelves.place(tab.id, into: folder, pins: pinSlots))
        writeSession(now: true)
    }

    func beginFolderRename(_ id: UUID) {
        editingFolder = id
    }

    /// Typed into the folder's row. Nothing but spaces keeps the old name: a
    /// folder with no name is a row you couldn't tell from the next.
    func renameFolder(_ id: UUID, to typed: String) {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name
    }

    func endFolderEdit() {
        guard editingFolder != nil else { return }
        editingFolder = nil
        writeSession(now: true)
    }

    /// Open or closed, remembered with the space.
    func toggleFolder(_ id: UUID) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].open.toggle()
        rememberSession()
    }

    /// The folder goes; its pins stay where they are, loose.
    func deleteFolder(_ id: UUID) {
        objectWillChange.send()
        if editingFolder == id { editingFolder = nil }
        for tab in tabs where tab.folder == id { tab.folder = nil }
        folders.removeAll { $0.id == id }
        tidyTabs()
        writeSession(now: true)
    }

    /// A pin row carried to another line among the pins as drawn.
    func movePinRow(_ tab: Tab, to row: Int) {
        reorderPins(Shelves.movePin(tab.id, to: row, pins: pinSlots, folders: folders, active: activeID))
        rememberSession()
    }

    /// A folder's row carried to another line, its pins with it.
    func moveFolderRow(_ id: UUID, to row: Int) {
        reorderPins(Shelves.moveFolder(id, to: row, pins: pinSlots, folders: folders, active: activeID))
        rememberSession()
    }

    /// The pins put in a new order, each with its folder; the favorites and
    /// the day's tabs are left where they are. The column draws from the
    /// browser, and a pin that only changed folder would otherwise publish
    /// nothing.
    private func reorderPins(_ pins: [Slot]) {
        let byID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let pinTabs = pins.compactMap { byID[$0.id] }
        let start = favoriteCount
        guard pinTabs.count == pinCount,
              Set(pinTabs.map(\.id)) == Set(tabs[start..<(start + pinCount)].map(\.id))
        else { return }
        objectWillChange.send()
        for slot in pins where byID[slot.id]?.folder != slot.folder { byID[slot.id]?.folder = slot.folder }
        var row = tabs
        row.replaceSubrange(start..<(start + pinTabs.count), with: pinTabs)
        if row.map(\.id) != tabs.map(\.id) { tabs = row }
        tidyTabs()
    }
```

- [ ] **Step 2: A space switch ends a folder rename**

In `Spaces.swift`'s `enter(_:)`, directly after the line `cancelTabEdit()`, add:

```swift
        editingFolder = nil
```

- [ ] **Step 3: The pin menu's folder lines**

In `TabBar.swift`, in `KeptTabCommands.body`, replace the pins branch:

```swift
        } else {
            Button("Move to Favorites") { browser.keep(tab, on: .favorites) }
            Button("Unpin") { browser.unpin(tab) }
        }
```

with:

```swift
        } else {
            Button("Move to Favorites") { browser.keep(tab, on: .favorites) }
            Button("New Folder with This Pin") { browser.newFolder(with: tab) }
            // The way into a closed folder, and to the end of any: a drag
            // reaches only the inside of an open one.
            let elsewhere = browser.folders.filter { $0.id != tab.folder }
            if !elsewhere.isEmpty {
                Menu("Move to Folder") {
                    ForEach(elsewhere) { folder in
                        Button(folder.name) { browser.putInFolder(tab, folder.id) }
                    }
                }
            }
            if tab.folder != nil {
                Button("Remove from Folder") { browser.putInFolder(tab, nil) }
            }
            Button("Unpin") { browser.unpin(tab) }
        }
```

- [ ] **Step 4: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then 58 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Search/Browser.swift Sources/Search/Spaces.swift Sources/Search/TabBar.swift
git commit -m "Folders of pins can be made, filled, emptied, renamed and deleted from a pin's menu"
```

---

### Task 4: Folders in the column

**Files:**
- Modify: `Sources/Search/Side.swift`:
  - the `SideBar` constants;
  - `pinRows`, `pinBlock` and `preview(_:pill:)`;
  - new private views `FolderRow` and `FolderField` at the end of the file.

**Interfaces:**
- Consumes:
  - `Browser.pinnedRows`, `folders`, `editingFolder`, `movePinRow`, `moveFolderRow`, `toggleFolder`, `beginFolderRename`, `renameFolder`, `endFolderEdit`, `deleteFolder` (Task 3);
  - `Browser.slots(of:)` (Task 2); `Shelves.pinnedRows` (Task 1);
  - `Carried`, `SideRow`, `Palette`, `Motion`.
- Produces: nothing new for other tasks.

- [ ] **Step 1: The indent**

In `struct SideBar`, after `private static let divider: CGFloat = 13`, add:

```swift
    /// How far a folder's pins sit in from the folder's own row.
    private static let indent: CGFloat = 14
```

- [ ] **Step 2: The pin rows draw the folders**

Replace the whole `private var pinRows: some View { … }` with:

```swift
    /// The pins: rows under the cards, for the pages kept all day that want
    /// their titles rather than a letter, and the folders that hold some of
    /// them — each folder's row, then its pins, indented, while it is open.
    /// A pin and a folder are carried the same way, through the rows as
    /// drawn; where one is let go decides its folder (see Shelves.movePin).
    private var pinRows: some View {
        let rows = browser.pinnedRows
        let step = SideBar.row + SideBar.gap
        return VStack(spacing: SideBar.gap) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                switch row {
                case .folder(let id):
                    if let folder = browser.folders.first(where: { $0.id == id }) {
                        FolderRow(browser: browser, folder: folder)
                            .modifier(Carried(index: index, count: rows.count, step: step, vertical: true, space: "pinRows") {
                                browser.moveFolderRow(id, to: $0)
                            })
                    }
                case .pin(let id, let folder):
                    if let tab = browser.tabs.first(where: { $0.id == id }) {
                        SideRow(
                            browser: browser,
                            prefs: prefs,
                            tab: tab,
                            live: tab.id == browser.activeID,
                            pill: pill,
                            close: { browser.close(tab) }
                        )
                        .padding(.leading, folder == nil ? 0 : SideBar.indent)
                        .modifier(Carried(index: index, count: rows.count, step: step, vertical: true, space: "pinRows") {
                            browser.movePinRow(tab, to: $0)
                        })
                    }
                }
            }
        }
        .coordinateSpace(name: "pinRows")
    }
```

- [ ] **Step 3: The block's height counts the drawn rows**

Replace the body of `private var pinBlock: CGFloat`:

```swift
        let pins = CGFloat(browser.pinCount)
        return pins == 0 ? 0 : pins * (SideBar.row + SideBar.gap) - SideBar.gap + SideBar.divider
```

with:

```swift
        let rows = CGFloat(browser.pinnedRows.count)
        return rows == 0 ? 0 : rows * (SideBar.row + SideBar.gap) - SideBar.gap + SideBar.divider
```

Update its doc comment's first line so it reads "The pinned rows as drawn (folder rows and the pins on show) and their divider…". Keep the rest.

- [ ] **Step 4: Another space's folders in its preview**

In `preview(_:pill:)`, replace:

```swift
            if !pinsAsRows.isEmpty {
                VStack(spacing: SideBar.gap) {
                    ForEach(pinsAsRows) { tab in
                        SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active, pill: pill, close: {})
                    }
                }
                divider
            }
```

with:

```swift
            if !pinsAsRows.isEmpty {
                let drawn = Shelves.pinnedRows(Browser.slots(of: pinsAsRows), folders: row.folders, active: row.active)
                VStack(spacing: SideBar.gap) {
                    ForEach(drawn) { line in
                        switch line {
                        case .folder(let id):
                            if let folder = row.folders.first(where: { $0.id == id }) {
                                FolderRow(browser: browser, folder: folder)
                            }
                        case .pin(let id, let folder):
                            if let tab = pinsAsRows.first(where: { $0.id == id }) {
                                SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active, pill: pill, close: {})
                                    .padding(.leading, folder == nil ? 0 : SideBar.indent)
                            }
                        }
                    }
                }
                divider
            }
```

The preview's root already has `.allowsHitTesting(false)`, so nothing here answers a click.

- [ ] **Step 5: `FolderRow` and `FolderField`**

At the end of `Side.swift`, add:

```swift

/// A folder among the pins, as a line in the column. A click opens or closes
/// it, a double-click renames it; the single click waits the moment a double
/// one takes to rule itself out.
private struct FolderRow: View {
    @ObservedObject var browser: Browser
    let folder: Folder

    @State private var hovering = false

    private var editing: Bool { browser.editingFolder == folder.id }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .rotationEffect(.degrees(folder.open ? 90 : 0))
                .frame(width: 10)
            Image(systemName: "folder")
                .font(.system(size: 11))
            if editing {
                FolderField(browser: browser, folder: folder)
                    .frame(height: 16)
            } else {
                Text(folder.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(hovering || editing ? Palette.ink.opacity(0.7) : Palette.muted)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if hovering {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.hover)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .gesture(
            TapGesture(count: 2)
                .onEnded { browser.beginFolderRename(folder.id) }
                .exclusively(before: TapGesture().onEnded {
                    withAnimation(Motion.settle) { browser.toggleFolder(folder.id) }
                })
        )
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Rename Folder") { browser.beginFolderRename(folder.id) }
            Button("Delete Folder") { browser.deleteFolder(folder.id) }
        }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: folder.open)
    }
}

/// A folder's name, typed over in place. It arrives selected, so a keystroke
/// replaces it. Return, Tab or a click elsewhere keeps what was typed; Escape
/// keeps the old name.
private struct FolderField: NSViewRepresentable {
    @ObservedObject var browser: Browser
    let folder: Folder

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser, id: folder.id) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12.5)
        field.textColor = Palette.NS.ink
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.stringValue = folder.name
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.browser = browser
        guard !coordinator.claimed else { return }
        coordinator.claimed = true
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var browser: Browser
        let id: UUID
        var claimed = false
        var cancelled = false

        init(browser: Browser, id: UUID) {
            self.browser = browser
            self.id = id
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                control.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                cancelled = true
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            if !cancelled { browser.renameFolder(id, to: field.stringValue) }
            browser.endFolderEdit()
        }
    }
}
```

`Palette.NS.ink` and `Palette.hover` are the names `PinField` (TabBar.swift) and `SideRow`'s ground already use. If the Swift 5 compiler complains about main-actor isolation in `Coordinator`, copy the exact isolation markings from `PinField.Coordinator` in TabBar.swift, which does the same thing.

- [ ] **Step 6: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then 58 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Search/Side.swift
git commit -m "Folders in the column: a row that opens and closes, its pins indented under it, renamed in place"
```

---

### Task 5: Bench, end-to-end check, changelog

**Files:**
- Modify: `Sources/Search/Bench.swift`: a new `case "folder":` directly before `case "text":`, and `"folder",` in the `"commands": [` list after `"home",`.
- Modify: `bench`: the docstring line after the `home` usage line, the request building after the `home` branch, and the output printing.
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Task 3's `Browser` folder API and `pinnedRows`.
- Produces: `./bench --test folder new ID NAME | into ID NAME | out ID | toggle NAME | delete NAME | rename NAME NEW | drag ID INDEX | dragfolder NAME INDEX | rows`. It answers with the drawn rows.

- [ ] **Step 1: The bench verb**

In `Bench.swift`, directly before `case "text":`, add:

```swift
        case "folder":
            // Folders of pins made, filled, moved and dropped, as their menus
            // and drags would. They change your row: only on a SEARCH_PROBE run.
            guard Store.testing else { answer(["error": "folder only works on a --test run — it changes your tabs"]); return }
            let named = browser.folders.first { $0.name == request["name"] as? String }
            switch request["what"] as? String ?? "rows" {
            case "new":
                guard let tab = find(request, in: browser) else { answer(missing(request)); return }
                browser.newFolder(with: tab)
                if let id = browser.editingFolder {
                    browser.renameFolder(id, to: request["name"] as? String ?? "Folder")
                    browser.endFolderEdit()
                }
            case "into":
                guard let tab = find(request, in: browser) else { answer(missing(request)); return }
                guard let named else { answer(["error": "no folder called that"]); return }
                browser.putInFolder(tab, named.id)
            case "out":
                guard let tab = find(request, in: browser) else { answer(missing(request)); return }
                browser.putInFolder(tab, nil)
            case "toggle", "delete", "rename", "dragfolder":
                guard let named else { answer(["error": "no folder called that"]); return }
                switch request["what"] as? String {
                case "toggle": browser.toggleFolder(named.id)
                case "delete": browser.deleteFolder(named.id)
                case "rename":
                    browser.beginFolderRename(named.id)
                    browser.renameFolder(named.id, to: request["to"] as? String ?? "")
                    browser.endFolderEdit()
                default: browser.moveFolderRow(named.id, to: request["index"] as? Int ?? 0)
                }
            case "drag":
                guard let tab = find(request, in: browser) else { answer(missing(request)); return }
                browser.movePinRow(tab, to: request["index"] as? Int ?? 0)
            case "rows":
                break
            default:
                answer(["error": "folder needs new, into, out, toggle, delete, rename, drag, dragfolder or rows"]); return
            }
            answer(["rows": browser.pinnedRows.map { row -> String in
                switch row {
                case .folder(let id):
                    let folder = browser.folders.first { $0.id == id }
                    return "FOLDER \(folder?.name ?? "?")" + (folder?.open == false ? " (closed)" : "")
                case .pin(let id, let folder):
                    let tab = browser.tabs.first { $0.id == id }
                    return (folder == nil ? "" : "  ") + "PIN \(tab.map(Bench.short) ?? "?") \(tab?.address?.path ?? "")"
                }
            }])

```

In the verb switch's final `default:` `"commands": [` list, add `"folder",` right after `"home",`.

- [ ] **Step 2: The client**

In `bench`, directly after the `elif verb == "home":` branch (its two lines), add:

```python
    elif verb == "folder":
        what, a = (args[0], args[1:]) if args else ("rows", [])
        need = {"new": 2, "into": 2, "out": 1, "toggle": 1, "delete": 1, "rename": 2, "drag": 2, "dragfolder": 2, "rows": 0}
        if what not in need or len(a) != need[what]:
            sys.exit("usage: bench folder new ID NAME|into ID NAME|out ID|toggle NAME|delete NAME|rename NAME NEW|drag ID INDEX|dragfolder NAME INDEX|rows")
        request["what"] = what
        if what in ("new", "into"): request["id"], request["name"] = a
        elif what == "out": request["id"] = a[0]
        elif what in ("toggle", "delete"): request["name"] = a[0]
        elif what == "rename": request["name"], request["to"] = a
        elif what == "drag": request["id"], request["index"] = a[0], int(a[1])
        elif what == "dragfolder": request["name"], request["index"] = a[0], int(a[1])
```

In the output section, directly before `elif verb == "tabs":`, add:

```python
    elif verb == "folder":
        for row in answer.get("rows", []):
            print(row)
```

In the docstring, after the `./bench home ID [go|set]` line, add:

```
    ./bench folder new ID NAME | into ID NAME | out ID | toggle NAME | delete NAME | rename NAME NEW
                 | drag ID INDEX | dragfolder NAME INDEX | rows
                                       folders of pins, and the pinned rows as drawn — --test runs only
```

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then 58 tests pass.

- [ ] **Step 3: Start the test run**

```bash
mkdir -p /tmp/folders-site && cd /tmp/folders-site && for p in a b c d e; do echo "<title>$p</title>" > $p; done && cd - >/dev/null
nohup python3 -m http.server 8765 --bind 127.0.0.1 --directory /tmp/folders-site >/dev/null 2>&1 & echo $! > /tmp/folders-server.pid
D="$HOME/Library/Application Support/Search (test)"
cp "$D/session.json" "$D/session.json.before-folders" 2>/dev/null || true
nohup .build/debug/Search >/tmp/search-test.log 2>&1 &
sleep 3 && ./bench --test tabs
```

Expected: a tab listing with no error. If the bench doesn't answer, set `defaults write com.officecommun.search.test bench -bool true` once and relaunch.

- [ ] **Step 4: Making and filling a folder, by drag**

```bash
A=$(./bench --test open http://127.0.0.1:8765/a); B=$(./bench --test open http://127.0.0.1:8765/b)
C=$(./bench --test open http://127.0.0.1:8765/c); D4=$(./bench --test open http://127.0.0.1:8765/d)
for id in $A $B $C $D4; do ./bench --test wait $id >/dev/null; ./bench --test keep $id pins >/dev/null; done
./bench --test folder new $A Work
```

Expected rows: `FOLDER Work`, `  PIN … /a`, `PIN … /b`, `PIN … /c`, `PIN … /d`.

```bash
./bench --test folder drag $B 1
```

Expected: `FOLDER Work`, `  PIN … /b`, `  PIN … /a`, `PIN … /c`, `PIN … /d`. Directly under an open folder's row, the pin joins.

```bash
./bench --test folder drag $C 2
```

Expected: `FOLDER Work`, `  PIN … /b`, `  PIN … /c`, `  PIN … /a`, `PIN … /d`. Between two of its pins, it joins.

```bash
./bench --test folder drag $A 4
```

Expected: `FOLDER Work`, `  PIN … /b`, `  PIN … /c`, `PIN … /d`, `PIN … /a`. Below the last pin, it leaves.

```bash
./bench --test folder drag $D4 0
```

Expected: `PIN … /d`, `FOLDER Work`, `  PIN … /b`, `  PIN … /c`, `PIN … /a`. Above the folder's row, it stays out.

(The variable is `D4`, not `D`, because `D` holds the test world's folder.)

- [ ] **Step 5: Closing, the menu's way in, and moving a folder**

```bash
./bench --test folder toggle Work
```

Expected: `PIN … /d`, `FOLDER Work (closed)`, `PIN … /a`.

```bash
./bench --test folder into $A Work
```

Expected: `PIN … /d`, `FOLDER Work`, `  PIN … /b`, `  PIN … /c`, `  PIN … /a`. Into a closed folder, it goes to the end, and the folder opens.

```bash
./bench --test folder toggle Work && ./bench --test folder dragfolder Work 0
```

Expected: `FOLDER Work (closed)`, `PIN … /d`. The closed folder moved above `/d`, taking its three pins with it. Check with `./bench --test tabs`: the pins are in the order b, c, a, d.

```bash
./bench --test folder out $B && ./bench --test folder toggle Work
```

Expected, after `out` (Work closed): `FOLDER Work (closed)`, `PIN … /b`, `PIN … /d`. After the toggle: `FOLDER Work`, `  PIN … /c`, `  PIN … /a`, `PIN … /b`, `PIN … /d`.

```bash
E=$(./bench --test open http://127.0.0.1:8765/e) && ./bench --test wait $E >/dev/null && ./bench --test keep $E pins >/dev/null
./bench --test folder new $E Side
./bench --test folder dragfolder Side 1
```

Expected: `FOLDER Side`, `  PIN … /e`, `FOLDER Work`, `  PIN … /c`, `  PIN … /a`, `PIN … /b`, `PIN … /d`. Carried up into Work, Side lands before Work's row, never between Work's pins.

- [ ] **Step 6: Rename and delete**

```bash
./bench --test folder rename Work Stuff && ./bench --test folder rename Stuff "   "
```

Expected: the first shows `FOLDER Stuff`. The second, with blank-only text, keeps `FOLDER Stuff`.

```bash
./bench --test folder delete Stuff
```

Expected: no `FOLDER Stuff` row. Its pins (c, a) are loose, in place and not indented. `./bench --test tabs` still lists them as `PIN`.

- [ ] **Step 7: Folders survive a relaunch, and a broken one doesn't cost the session**

```bash
pkill -f "\.build/debug/Search"; sleep 1
cat > "$D/session.json" <<'EOF'
{"tabs":[
  {"url":"http://127.0.0.1:8765/a","title":"a","pin":"A","shelf":"pins","home":"http://127.0.0.1:8765/a","folder":"F0000000-0000-0000-0000-00000000000A"},
  {"url":"http://127.0.0.1:8765/b","title":"b","pin":"B","shelf":"pins","home":"http://127.0.0.1:8765/b","folder":"F0000000-0000-0000-0000-00000000000A"},
  {"url":"http://127.0.0.1:8765/c","title":"c","pin":"C","shelf":"pins","home":"http://127.0.0.1:8765/c","folder":"F0000000-0000-0000-0000-00000000000B"},
  {"url":"http://127.0.0.1:8765/d","title":"d"}
],"active":3,
 "folders":[{"id":"F0000000-0000-0000-0000-00000000000A","name":"Kept","open":false},{"broken":true}]}
EOF
nohup .build/debug/Search >/tmp/search-test.log 2>&1 &
sleep 3 && ./bench --test folder rows && ./bench --test tabs
```

Expected:
- rows: `FOLDER Kept (closed)`, then `PIN … /c`, which is loose because its folder was the broken entry;
- tabs: all four tabs are there, with pins a, b, c and today's tab d.

- [ ] **Step 8: The column: picture and drag area**

Open Kept (`./bench --test folder toggle Kept`). If the test world shows tabs across the top, run `./bench --test ui sidebar on`.

```bash
./bench --test column /tmp/folders-column.png
for y in $(seq 40 10 400); do printf "%s " $y; ./bench --test hit 60 $y | tr -d '\n' | head -c 160; echo; done
```

Expected: the PNG shows a `Kept` folder row with a turned chevron, a and b indented under it, c flush left, the divider, then today's tabs and New tab.

In the `hit` scan, the `view` field is what tells the areas apart: `Strip` means a drag moves the window, and anything else is content. `windowMovable`/`canMoveWindow` are constant. The scan should change from content to `Strip` within one row of the bottom of "New tab". Record the Y where it switches.

- [ ] **Step 9: Clean up**

```bash
./bench --test ui sidebar off   # only if Step 8 turned it on
pkill -f "\.build/debug/Search"; kill "$(cat /tmp/folders-server.pid)"
[ -f "$D/session.json.before-folders" ] && mv "$D/session.json.before-folders" "$D/session.json"
pgrep -fl "\.build/debug/Search|http.server 8765" || echo "clean"
```

Expected: `clean`.

- [ ] **Step 10: Changelog**

In `CHANGELOG.md`, under `## Unreleased` › `### Added`, add this as the first line of the list:

```markdown
- Folders among the pins, as in Arc: New Folder with This Pin from a pin's menu, a click on the folder's row to open or close it, a double-click to rename it. Drag a pin between a folder's pins, or right under an open folder, and it joins; drag it out past either end and it leaves; Move to Folder reaches a closed one. Drag a folder's row and its pins go with it. The tab you're on stays in sight under a closed folder.
```

- [ ] **Step 11: Commit**

```bash
git add Sources/Search/Bench.swift bench CHANGELOG.md
git commit -m "The bench can make and move folders of pins, and the changelog says what folders are"
```

The controller pushes `sidebar-folders` and opens its PR after the final review:
`gh pr create --repo Richard-DEPIERRE/Search --base sidebar-pins --head sidebar-folders`.
