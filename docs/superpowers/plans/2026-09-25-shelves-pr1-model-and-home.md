# Shelves PR 1 — model, migration, pins that go back to their page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every kept tab a shelf (favorites or pins), a home page it goes back to, and an optional folder. Migrate today's pins to favorites with no visible change except the new "away" dot and the Back / Set Pinned Page actions.

**Architecture:** The ordering and "is it home?" rules live in a new pure file, `Shelves.swift` (no WebKit, no SwiftUI), which a new Swift Testing target covers. `Tab` gains `shelf`, `home`, `landed` and `folder`. `Browser` keeps `tabs` flat and calls `Shelves.tidy` after every change to kept tabs and after every load. `Session` gains optional fields, so old files read as favorites.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftPM, AppKit + SwiftUI + WebKit, Swift Testing, and the repo's `./bench` socket harness.

**Spec:** `docs/superpowers/specs/2026-09-25-sidebar-favorites-pins-folders-design.md`. This plan is **PR 1** of §5. PR 2 (pinned rows) and PR 3 (folders UI) get their own plans.

## Global Constraints

- macOS 14 or later (`platforms: [.macOS(.v14)]`). No dependencies beyond what Apple ships.
- Swift language mode v5 for every target (`swiftSettings: [.swiftLanguageMode(.v5)]`).
- `pin != nil` keeps its meaning: the tab is *kept* (a favorite or a pin).
- New `Session` fields are optional. An old `session.json` must decode, and a kept entry with no `shelf` is a **favorite** with `home = url`.
- No settings switch: this replaces behaviour (owner's decision).
- ⌘W on a kept tab: the page unloads and the tab goes back to `home` (falling back to `address`).
- "Away" comparison: drop the `#fragment` and a trailing `/`, lowercase the scheme and host; the rest must match exactly. `landed` counts as home.
- `Shelves.swift` imports Foundation only.
- Comments follow the repo's voice: plain sentences explaining *why*, and no attribution lines in commits or PR bodies.
- PRs go only to the fork: `gh pr create --repo Richard-DEPIERRE/Search --base main`. Never run `./ideas`.
- CHANGELOG.md: one line under `## Unreleased` › `### Added`.

## Review Focus

1. **A home page that redirects on the way in** (for example `mail.google.com/` → `/mail/u/0/`): after ⌘W and a click, or after Back to Pinned Page, the tab must *not* show the away dot. Pinned by `isHome` tests in Task 1 and the redirect check in Task 6, Step 5.
2. **Relaunching on an old `session.json`** that has only `pin`: every pin is still there, in the same order, as a favorite whose home is its saved URL. Pinned by `SessionTests` in Task 2 and the seeded-file check in Task 6, Step 6.
3. **Switching spaces and back** keeps each kept tab's shelf, home and the space's folders. Pinned by the `Parked.folders` wiring in Task 4 and the space check in Task 6, Step 7.
4. **A hand-edited or half-written session** (an unknown `shelf` string, a folder id that doesn't exist, a folder on a favorite, pins of one folder scattered): it loads without breaking the order. Pinned by the `tidy` and `keptShelf` tests in Tasks 1–2.
5. **A blank tab or a tab with no address** is never "away", and Set Pinned Page is disabled for it. Pinned by the `isHome(nil…)` test in Task 1 and the menu `.disabled` in Task 5.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `Package.swift` | Modify | Add the `SearchTests` test target. |
| `Sources/Search/Shelves.swift` | **Create** | `Shelf`, `Folder`, `Slot`, and `Shelves` (sections, `tidy`, `canMove`, `normalised`, `isHome`). Pure: Foundation only. |
| `Tests/SearchTests/ShelvesTests.swift` | **Create** | Tests for `Shelves`. |
| `Sources/Search/Session.swift` | Modify | New optional `Entry` fields and `Shape.folders`; `keptShelf`, `keptHome`, `folderID`. |
| `Tests/SearchTests/SessionTests.swift` | **Create** | Migration and round-trip tests. |
| `Sources/Search/Tab.swift` | Modify | `shelf`, `home`, `landed`, `folder`, `homing`, `away`; `remember(home:)`, `forgetHome()`, `goHome()`; `rest()` goes home; `wake()` and the URL/loading observers track `landed`. |
| `Sources/Search/Browser.swift` | Modify | `folders`, `slots`, `tidyTabs`, `tidied(_:folders:)`; `pin`/`unpin`/`move`/`restoreSession`/`loadRow`/`writeSession`/`showRow`; `goHome`, `setHome`. |
| `Sources/Search/Spaces.swift` | Modify | `Parked.folders`, and carry it through `enter`. |
| `Sources/Search/Side.swift` | Modify | The new `AwayDot` view, and the dot on `PinSquare`. |
| `Sources/Search/TabBar.swift` | Modify | The dot on a pinned `TabPill`; `TabMenu` labels and the new actions. |
| `Sources/Search/App.swift` | Modify | Tabs menu labels and the new actions. |
| `Sources/Search/Bench.swift` | Modify | `describe` fields; `keep` and `home` verbs. |
| `bench` | Modify | Client for `keep` and `home`; usage text; `FAV`/`PIN`/away in `tabs` output. |
| `CHANGELOG.md` | Modify | One "Added" line. |

---

### Task 1: The shelf rules, and a test target to hold them

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Search/Shelves.swift`
- Test: `Tests/SearchTests/ShelvesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Tasks 2–6):
  - `enum Shelf: String, Codable { case favorites, pins }`
  - `struct Folder: Codable, Identifiable, Equatable { var id: UUID; var name: String; var open: Bool }`
  - `struct Slot: Equatable { var id: UUID; var kept: Bool; var shelf: Shelf; var folder: UUID? }`
  - `enum Shelves`, with:
    - `enum Section: Int, Comparable { case favorites, pins, loose }`
    - `static func section(of: Slot) -> Section`
    - `static func tidy(_ slots: [Slot], folders: [Folder]) -> (slots: [Slot], folders: [Folder])`
    - `static func canMove(_ slots: [Slot], from: Int, to: Int) -> Bool`
    - `static func normalised(_ url: URL) -> String`
    - `static func isHome(_ address: URL?, home: URL?, landed: URL?) -> Bool`

- [ ] **Step 1: Add the test target**

Replace the whole `Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Search",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Search",
            path: "Sources/Search",
            // Same reasoning as the canvas app next door: the whole interface is
            // main-thread by nature, and Swift 6's strict isolation buys nothing
            // here but ceremony.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The rules that need no window: the order of the row, what counts
        // as a kept tab's own page, what an old session file means.
        .testTarget(
            name: "SearchTests",
            dependencies: ["Search"],
            path: "Tests/SearchTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/SearchTests/ShelvesTests.swift`:

```swift
import Foundation
import Testing
@testable import Search

private func slot(_ n: Int, kept: Bool = false, _ shelf: Shelf = .favorites, folder: UUID? = nil) -> Slot {
    Slot(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, kept: kept, shelf: shelf, folder: folder)
}

private let work = Folder(id: UUID(uuidString: "F0000000-0000-0000-0000-000000000001")!, name: "Work", open: true)
private let play = Folder(id: UUID(uuidString: "F0000000-0000-0000-0000-000000000002")!, name: "Play", open: false)

@Suite struct TidyTests {
    @Test func sectionsComeInOrderAndKeepTheirOwnOrder() {
        let row = [slot(1), slot(2, kept: true, .pins), slot(3, kept: true), slot(4), slot(5, kept: true)]
        let (out, _) = Shelves.tidy(row, folders: [])
        #expect(out.map(\.id) == [row[2].id, row[4].id, row[1].id, row[0].id, row[3].id])
    }

    @Test func aFolderOnSomethingThatIsNotAPinIsDropped() {
        let row = [slot(1, kept: true, .favorites, folder: work.id), slot(2, folder: work.id), slot(3, kept: true, .pins, folder: work.id)]
        let (out, folders) = Shelves.tidy(row, folders: [work])
        #expect(out.first { $0.id == row[0].id }?.folder == nil)
        #expect(out.first { $0.id == row[1].id }?.folder == nil)
        #expect(out.first { $0.id == row[2].id }?.folder == work.id)
        #expect(folders == [work])
    }

    @Test func anUnknownFolderIsDropped() {
        let ghost = UUID()
        let (out, folders) = Shelves.tidy([slot(1, kept: true, .pins, folder: ghost)], folders: [work])
        #expect(out[0].folder == nil)
        #expect(folders.isEmpty)
    }

    @Test func aFolderWithNothingInItGoes() {
        let (_, folders) = Shelves.tidy([slot(1, kept: true, .pins, folder: work.id)], folders: [work, play])
        #expect(folders == [work])
    }

    @Test func aFoldersPinsAreGatheredWhereItsFirstPinIs() {
        let row = [
            slot(1, kept: true, .pins, folder: work.id),
            slot(2, kept: true, .pins),
            slot(3, kept: true, .pins, folder: work.id),
            slot(4, kept: true, .pins, folder: play.id),
        ]
        let (out, folders) = Shelves.tidy(row, folders: [work, play])
        #expect(out.map(\.id) == [row[0].id, row[2].id, row[1].id, row[3].id])
        #expect(folders == [work, play])
    }

    @Test func anOrderlyRowIsLeftAlone() {
        let row = [slot(1, kept: true), slot(2, kept: true, .pins, folder: work.id), slot(3, kept: true, .pins), slot(4)]
        let (out, folders) = Shelves.tidy(row, folders: [work])
        #expect(out == row)
        #expect(folders == [work])
    }
}

@Suite struct MoveTests {
    let row = [slot(1, kept: true), slot(2, kept: true), slot(3, kept: true, .pins), slot(4), slot(5)]

    @Test func withinASectionIsAllowed() {
        #expect(Shelves.canMove(row, from: 0, to: 1))
        #expect(Shelves.canMove(row, from: 3, to: 4))
    }

    @Test func acrossSectionsIsNot() {
        #expect(!Shelves.canMove(row, from: 1, to: 2))
        #expect(!Shelves.canMove(row, from: 2, to: 3))
        #expect(!Shelves.canMove(row, from: 4, to: 0))
    }

    @Test func outOfRangeIsNot() {
        #expect(!Shelves.canMove(row, from: 0, to: 9))
        #expect(!Shelves.canMove(row, from: -1, to: 0))
    }
}

@Suite struct HomeTests {
    let home = URL(string: "https://mail.example.com/")!

    @Test func theSamePageIsHome() {
        #expect(Shelves.isHome(URL(string: "https://mail.example.com/")!, home: home, landed: nil))
    }

    @Test func aFragmentOrATrailingSlashIsStillHome() {
        #expect(Shelves.isHome(URL(string: "https://mail.example.com#inbox")!, home: home, landed: nil))
        #expect(Shelves.isHome(URL(string: "https://MAIL.example.com")!, home: home, landed: nil))
        #expect(Shelves.isHome(URL(string: "https://a.com/x/#top")!, home: URL(string: "https://a.com/x")!, landed: nil))
    }

    @Test func whereTheTripHomeLandedIsHome() {
        let landed = URL(string: "https://mail.example.com/mail/u/0/")!
        #expect(Shelves.isHome(URL(string: "https://mail.example.com/mail/u/0/#inbox")!, home: home, landed: landed))
    }

    @Test func anotherPathOrQueryIsAway() {
        #expect(!Shelves.isHome(URL(string: "https://mail.example.com/settings")!, home: home, landed: nil))
        #expect(!Shelves.isHome(URL(string: "https://mail.example.com/?q=1")!, home: home, landed: nil))
        #expect(!Shelves.isHome(URL(string: "https://other.example.com/")!, home: home, landed: nil))
    }

    @Test func noAddressOrNoHomeIsNeverAway() {
        #expect(Shelves.isHome(nil, home: home, landed: nil))
        #expect(Shelves.isHome(URL(string: "https://a.com")!, home: nil, landed: nil))
    }
}
```

- [ ] **Step 3: Run the tests and check they fail**

Run: `swift test 2>&1 | tail -20`
Expected: a compile failure, `cannot find 'Slot' in scope` / `cannot find 'Shelves' in scope`.

- [ ] **Step 4: Write `Shelves.swift`**

Create `Sources/Search/Shelves.swift`:

```swift
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
}
```

- [ ] **Step 5: Run the tests and check they pass**

Run: `swift test 2>&1 | tail -20`
Expected: `✔ Test run with 14 tests in 3 suites passed` (6 tidy + 3 move + 5 home).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/Search/Shelves.swift Tests/SearchTests/ShelvesTests.swift
git commit -m "The rules for favorites, pins and folders, with tests of their own"
```

---

### Task 2: Session file — new optional fields and the migration

**Files:**
- Modify: `Sources/Search/Session.swift:8-19`
- Test: `Tests/SearchTests/SessionTests.swift`

**Interfaces:**
- Consumes: `Shelf`, `Folder` (Task 1).
- Produces (used by Task 4):
  - `Session.Entry` with new optional `shelf: String?`, `home: String?` and `folder: String?`, plus the computed:
    - `keptShelf: Shelf`
    - `keptHome: URL?`
    - `folderID: UUID?`
  - `Session.Shape` gains `folders: [Folder]?`. The memberwise init still accepts `Shape(tabs:active:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SearchTests/SessionTests.swift`:

```swift
import Foundation
import Testing
@testable import Search

@Suite struct SessionTests {
    /// A session.json as every version before shelves wrote it.
    let old = """
    {"tabs":[
      {"url":"https://mail.example.com/","title":"Mail","pin":"M"},
      {"url":"https://news.example.com/a","title":"A story"},
      {"url":"https://cal.example.com/week","title":"Calendar","pin":"C","name":"Cal"}
    ],"active":1}
    """

    @Test func anOldFileReadsWithItsPinsAsFavoritesAtHome() throws {
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(old.utf8))
        #expect(shape.tabs.count == 3)
        #expect(shape.folders == nil)
        #expect(shape.tabs[0].keptShelf == .favorites)
        #expect(shape.tabs[0].keptHome == URL(string: "https://mail.example.com/"))
        #expect(shape.tabs[2].keptHome == URL(string: "https://cal.example.com/week"))
        #expect(shape.tabs[2].name == "Cal")
    }

    @Test func aTabNotKeptHasNoHomeAndNoFolder() throws {
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(old.utf8))
        #expect(shape.tabs[1].keptHome == nil)
        #expect(shape.tabs[1].folderID == nil)
    }

    @Test func anUnknownShelfIsAFavorite() {
        let entry = Session.Entry(url: "https://a.com", title: "", pin: "A", shelf: "shelves")
        #expect(entry.keptShelf == .favorites)
    }

    @Test func aNewFileSurvivesTheRoundTrip() throws {
        let folder = Folder(id: UUID(), name: "Work", open: false)
        let shape = Session.Shape(
            tabs: [
                .init(url: "https://a.com/x", title: "A", pin: "A", shelf: "pins",
                      home: "https://a.com/", folder: folder.id.uuidString),
                .init(url: "https://b.com", title: "B"),
            ],
            active: 0,
            folders: [folder]
        )
        let back = try JSONDecoder().decode(Session.Shape.self, from: JSONEncoder().encode(shape))
        #expect(back.tabs[0].keptShelf == .pins)
        #expect(back.tabs[0].keptHome == URL(string: "https://a.com/"))
        #expect(back.tabs[0].folderID == folder.id)
        #expect(back.folders == [folder])
        #expect(back.tabs[1].keptHome == nil)
    }
}
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `swift test 2>&1 | tail -20`
Expected: a compile failure, `value of type 'Session.Entry' has no member 'keptShelf'` / `extra argument 'shelf'`.

- [ ] **Step 3: Update `Session.swift`**

Replace lines 8–19 (the `Entry` and `Shape` structs) with:

```swift
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
        /// page it was on, which is the page it was put down at.
        var keptHome: URL? {
            guard pin != nil else { return nil }
            return URL(string: home ?? url)
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
```

- [ ] **Step 4: Run the tests and check they pass**

Run: `swift test 2>&1 | tail -20`
Expected: `✔ Test run with 18 tests in 4 suites passed`.

- [ ] **Step 5: Build the app**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`. `Browser.writeSession` still builds `Session.Entry(url:title:pin:name:)`, because the new optional fields default to nil.

- [ ] **Step 6: Commit**

```bash
git add Sources/Search/Session.swift Tests/SearchTests/SessionTests.swift
git commit -m "The session keeps each kept tab's shelf, home and folder; an old one reads as favorites"
```

---

### Task 3: A tab knows its home, and when it has wandered from it

**Files:**
- Modify: `Sources/Search/Tab.swift`, in four places:
  - near line 366, the `pin` property;
  - near line 476, the `\.url` observer;
  - near line 497, the `\.isLoading` observer;
  - near lines 786–803 (`rest()`) and 984–1003 (`wake()`).

**Interfaces:**
- Consumes: `Shelf`, `Shelves.isHome`, `Shelves.normalised` (Task 1).
- Produces (used by Tasks 4–6), on `Tab`:
  - `@Published var shelf: Shelf`
  - `@Published private(set) var home: URL?`
  - `@Published private(set) var landed: URL?`
  - `@Published var folder: UUID?`
  - `var away: Bool`
  - `func remember(home: URL?)`
  - `func forgetHome()`
  - `func goHome()`

There is no unit test here, because a `Tab` builds a WKWebView. Its rules are the `Shelves` functions already tested in Task 1, and the behaviour is checked end to end with the bench in Task 6.

- [ ] **Step 1: Add the properties**

In `Tab.swift`, directly after the `@Published var pin: String?` declaration (line 366) and before the `name` doc comment, insert:

```swift

    /// Which kind of kept tab it is — a card at the top of the column or a
    /// row under them — whenever `pin` says it is kept.
    @Published var shelf: Shelf = .favorites

    /// The page it was kept at, and goes back to: ⌘W puts it down there, and
    /// the back button takes it there. Nil for a tab that isn't kept.
    @Published private(set) var home: URL?

    /// Where the last trip home actually arrived, redirects and all. It
    /// counts as home: a site that sends its front page on to an inbox
    /// hasn't taken you anywhere. Not saved; the next trip finds it again.
    @Published private(set) var landed: URL?

    /// The folder it sits in, for a pin in one.
    @Published var folder: UUID?

    /// From a trip home starting until the page has finished arriving: every
    /// address it passes through meanwhile is still home.
    private var homing = false

    /// Kept, and on some page other than the one it was kept at.
    var away: Bool {
        pin != nil && home != nil && !Shelves.isHome(address, home: home, landed: landed)
    }

    /// Kept at this page.
    func remember(home url: URL?) {
        home = url
        landed = nil
        homing = false
    }

    /// No longer kept: no page to go back to, no folder to be in.
    func forgetHome() {
        home = nil
        landed = nil
        homing = false
        folder = nil
    }

    /// Back to the page it was kept at, in place, awake.
    func goHome() {
        guard let home else { return }
        landed = nil
        homing = true
        go(to: home)
    }
```

- [ ] **Step 2: Record where a trip home lands**

In the `\.url` observer, find:

```swift
                    let moved = fresh.host() != self.address?.host()
                    self.address = fresh
                    if moved { self.adoptIcon() }
```

and replace it with:

```swift
                    let moved = fresh.host() != self.address?.host()
                    self.address = fresh
                    if self.homing { self.landed = fresh }
                    if moved { self.adoptIcon() }
```

- [ ] **Step 3: End the trip when the page has arrived**

Replace the `\.isLoading` observer:

```swift
            web.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.loading = self?.built?.isLoading ?? false }
            },
```

with:

```swift
            web.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.loading = self.built?.isLoading ?? false
                    // Arrived: anything after this is you going somewhere.
                    if !self.loading { self.homing = false }
                }
            },
```

- [ ] **Step 4: ⌘W puts a kept tab down at its home**

In `rest()`, replace its first two lines:

```swift
        guard let url = address else { return }
        pending = url
```

with:

```swift
        // Put down at the page it was kept at, as in Arc: the next click
        // opens it there, not wherever it had wandered off to.
        guard let url = (pin != nil ? home : nil) ?? address else { return }
        if url != address {
            address = url
            title = ""
            adoptIcon()
        }
        pending = url
```

- [ ] **Step 5: Waking at home is a trip home**

In `wake()`, directly after `guard let url = pending else { return false }`, insert:

```swift
        // Woken at the page it was kept at — after ⌘W, or from the session —
        // wherever that page sends it on the way in is still home.
        if let home, Shelves.normalised(url) == Shelves.normalised(home) {
            landed = nil
            homing = true
        }
```

- [ ] **Step 6: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then `✔ Test run with 18 tests in 4 suites passed`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Search/Tab.swift
git commit -m "A kept tab remembers its page, knows when it has left it, and is put down there"
```

---

### Task 4: The browser keeps the row in its order, and saves and restores shelves

**Files:**
- Modify: `Sources/Search/Browser.swift`:
  - `pin` / `unpin` (lines 528–584);
  - `restoreSession` (840–872);
  - `writeSession` (990–1010);
  - `move` (1226–1237);
  - `loadRow` / `showRow` (1435–1458).
- Modify: `Sources/Search/Spaces.swift:145-148` (`Parked`) and `:179-189` (`enter`).

**Interfaces:**
- Consumes: `Slot`, `Shelves.tidy`, `Shelves.canMove`, `Folder` (Task 1); `Entry.keptShelf/keptHome/folderID`, `Shape.folders` (Task 2); `Tab.shelf/home/folder/remember(home:)/forgetHome()/goHome()` (Task 3).
- Produces (used by Tasks 5–6), on `Browser`:
  - `@Published var folders: [Folder]`
  - `func tidyTabs()`
  - `static func tidied(_ row: [Tab], folders: [Folder]) -> (tabs: [Tab], folders: [Folder])`
  - `func goHome(_ tab: Tab)`
  - `func setHome(_ tab: Tab)`
  - `Parked.folders: [Folder]`, which defaults to `[]`
  - `showRow(_:active:folders:)`, where `folders` defaults to `[]`

- [ ] **Step 1: Add the folders, the slot view and tidying**

In `Browser.swift`, directly after `var pinnedCount: Int { tabs.filter { $0.pin != nil }.count }` (line 528), insert:

```swift

    /// This space's folders of pins (see Shelves.swift). Saved with its tabs,
    /// and parked with them while another space is on screen.
    @Published var folders: [Folder] = []

    /// The row as the shelf rules see it.
    private var slots: [Slot] { Browser.slots(of: tabs) }

    private static func slots(of row: [Tab]) -> [Slot] {
        row.map { Slot(id: $0.id, kept: $0.pin != nil, shelf: $0.shelf, folder: $0.folder) }
    }

    /// A row put in its order — favorites, pins with each folder's together,
    /// then the rest — and the folders still holding something. For a row
    /// on screen or one being made for a space that isn't.
    static func tidied(_ row: [Tab], folders: [Folder]) -> (tabs: [Tab], folders: [Folder]) {
        let (order, kept) = Shelves.tidy(slots(of: row), folders: folders)
        let byID = Dictionary(uniqueKeysWithValues: row.map { ($0.id, $0) })
        let tabs = order.compactMap { slot -> Tab? in
            guard let tab = byID[slot.id] else { return nil }
            if tab.folder != slot.folder { tab.folder = slot.folder }
            return tab
        }
        return (tabs, kept)
    }

    /// After anything that changes which tabs are kept, or where.
    func tidyTabs() {
        let (order, kept) = Browser.tidied(tabs, folders: folders)
        if order.map(\.id) != tabs.map(\.id) { tabs = order }
        if kept != folders { folders = kept }
    }
```

- [ ] **Step 2: Pinning makes a favorite at its home; unpinning lets the home go**

In `func pin(_ tab: Tab)`, replace:

```swift
        if tab.pin == nil {
            tab.pin = tab.monogram
            // Pinned tabs live at the head of the row, in the order they were
            // pinned, so their letters never move under your hand.
            if let here = tabs.firstIndex(where: { $0.id == tab.id }) {
                let home = max(0, pinnedCount - 1)
                if here != home {
                    tabs.move(
                        fromOffsets: IndexSet(integer: here),
                        toOffset: home > here ? home + 1 : home
                    )
                }
            }
        }
```

with:

```swift
        if tab.pin == nil {
            tab.pin = tab.monogram
            tab.shelf = .favorites
            // The page it is on is the page it goes back to.
            tab.remember(home: tab.address)
            // Favorites live at the head of the row, in the order they were
            // added, so their letters never move under your hand: tidying
            // leaves the others where they are and puts this one after them.
            tidyTabs()
        }
```

Keep the rest of `pin`, from `// No dialog and no waiting cursor` through `writeSession(now: true)`, as it is.

Then replace the whole of `func unpin(_ tab: Tab)`:

```swift
    func unpin(_ tab: Tab) {
        if editingPin == tab.id { editingPin = nil }
        tab.pin = nil
        defer { writeSession(now: true) }
        // Back out of the pinned block, to the head of the loose tabs.
        if let here = tabs.firstIndex(where: { $0.id == tab.id }) {
            let home = pinnedCount
            if here != home {
                tabs.move(fromOffsets: IndexSet(integer: here), toOffset: home > here ? home + 1 : home)
            }
        }
        rememberSession()
    }
```

with:

```swift
    func unpin(_ tab: Tab) {
        if editingPin == tab.id { editingPin = nil }
        tab.pin = nil
        tab.shelf = .favorites
        tab.forgetHome()
        // Out of the kept block, to the head of the loose tabs: it was in
        // front of every one of them, and tidying keeps it there.
        tidyTabs()
        writeSession(now: true)
    }

    /// Back to the page a favorite or pin was kept at.
    func goHome(_ tab: Tab) {
        guard tab.pin != nil else { return }
        if activeID != tab.id { select(tab) }
        tab.goHome()
        rememberSession()
    }

    /// The page it is on becomes the page it goes back to.
    func setHome(_ tab: Tab) {
        guard tab.pin != nil, let url = tab.address else { return }
        tab.remember(home: url)
        writeSession(now: true)
    }
```

- [ ] **Step 3: A drag stays within its own kind**

In `func move(_ tab: Tab, to index: Int)`, replace:

```swift
        // The pinned block and the loose one don't mix: a letter that wandered
        // into the middle of the titles would stop meaning anything.
        let pinned = pinnedCount
        if tab.pin != nil, index >= pinned { return }
        if tab.pin == nil, index < pinned { return }
```

with:

```swift
        // Favorites, pins and the rest don't mix: a letter that wandered into
        // the middle of the titles would stop meaning anything.
        guard Shelves.canMove(slots, from: here, to: index) else { return }
```

- [ ] **Step 4: Save the shelves**

In `writeSession`, replace:

```swift
                    return Session.Entry(
                        url: url.absoluteString, title: tab.title, pin: tab.pin, name: tab.name
                    )
                },
                active: tabs.firstIndex { $0.id == activeID } ?? 0
```

with:

```swift
                    let kept = tab.pin != nil
                    return Session.Entry(
                        url: url.absoluteString, title: tab.title, pin: tab.pin, name: tab.name,
                        shelf: kept ? tab.shelf.rawValue : nil,
                        home: kept ? tab.home?.absoluteString : nil,
                        folder: kept ? tab.folder?.uuidString : nil
                    )
                },
                active: tabs.firstIndex { $0.id == activeID } ?? 0,
                folders: folders.isEmpty ? nil : folders
```

- [ ] **Step 5: Restore the shelves**

In `restoreSession`, replace:

```swift
            tab.restore(url: url, title: entry.title, name: entry.name)
            tab.pin = entry.pin
            tabs.append(tab)
        }
        guard !tabs.isEmpty else {
            adopt(Tab())
            return
        }
        let here = min(max(0, saved.active), tabs.count - 1)
        activeID = tabs[here].id
        // Only the one you were looking at actually loads.
        tabs[here].wake()
```

with:

```swift
            tab.restore(url: url, title: entry.title, name: entry.name)
            tab.pin = entry.pin
            tab.shelf = entry.keptShelf
            tab.remember(home: entry.keptHome)
            tab.folder = entry.folderID
            tabs.append(tab)
        }
        guard !tabs.isEmpty else {
            adopt(Tab())
            return
        }
        // Chosen by where it was in the file, before tidying moves anything.
        let chosen = tabs[min(max(0, saved.active), tabs.count - 1)]
        activeID = chosen.id
        folders = saved.folders ?? []
        tidyTabs()
        // Only the one you were looking at actually loads.
        chosen.wake()
```

In `loadRow`, replace:

```swift
            tab.restore(url: url, title: entry.title, name: entry.name)
            tab.pin = entry.pin
            row.append(tab)
        }
        let active = row.indices.contains(saved.active) ? row[saved.active].id : row.first?.id
        return Parked(tabs: row, active: active)
```

with:

```swift
            tab.restore(url: url, title: entry.title, name: entry.name)
            tab.pin = entry.pin
            tab.shelf = entry.keptShelf
            tab.remember(home: entry.keptHome)
            tab.folder = entry.folderID
            row.append(tab)
        }
        let active = row.indices.contains(saved.active) ? row[saved.active].id : row.first?.id
        let (tidy, folders) = Browser.tidied(row, folders: saved.folders ?? [])
        return Parked(tabs: tidy, active: active, folders: folders)
```

Replace `showRow`:

```swift
    func showRow(_ row: [Tab], active: Tab.ID?) {
        tabs = row
        activeID = active ?? row.first?.id
    }
```

with:

```swift
    func showRow(_ row: [Tab], active: Tab.ID?, folders: [Folder] = []) {
        tabs = row
        self.folders = folders
        activeID = active ?? row.first?.id
    }
```

- [ ] **Step 6: Spaces park their folders with their tabs**

In `Spaces.swift`, replace:

```swift
struct Parked {
    var tabs: [Tab]
    var active: Tab.ID?
}
```

with:

```swift
struct Parked {
    var tabs: [Tab]
    var active: Tab.ID?
    /// Its folders of pins, which go where its tabs go.
    var folders: [Folder] = []
}
```

In `enter(_:)`, replace `parked[spaceID] = Parked(tabs: tabs, active: activeID)` with:

```swift
        parked[spaceID] = Parked(tabs: tabs, active: activeID, folders: folders)
```

and replace `showRow(back.tabs, active: back.active)` with:

```swift
            showRow(back.tabs, active: back.active, folders: back.folders)
```

- [ ] **Step 7: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then `✔ Test run with 18 tests in 4 suites passed`.

- [ ] **Step 8: Commit**

```bash
git add Sources/Search/Browser.swift Sources/Search/Spaces.swift
git commit -m "The row stays in its order of favorites, pins and tabs, and each space saves and parks its shelves"
```

---

### Task 5: The away dot, and the menus that go home

**Files:**
- Modify: `Sources/Search/Side.swift`: add `AwayDot` after `PinSquare`, and use it in `PinSquare.body` (lines 504–540).
- Modify: `Sources/Search/TabBar.swift`, the pinned branch of `TabPill.body` (lines 372–389) and `TabMenu.body` (lines 751–758).
- Modify: `Sources/Search/App.swift:119-127` (the Tabs menu).

**Interfaces:**
- Consumes: `Tab.away` (Task 3); `Browser.goHome(_:)`, `Browser.setHome(_:)`, `Browser.pin(_:)`, `Browser.unpin(_:)` (Task 4).
- Produces: `struct AwayDot: View { let size: CGFloat }` (internal, used by Side.swift and TabBar.swift).

- [ ] **Step 1: The dot**

In `Side.swift`, directly after the closing brace of `private struct PinSquare` (the line before `/// One tab, as a line in the column.`), insert:

```swift

/// Under a favorite that has left its page: a small mark, not a badge —
/// enough to find the square that isn't where you left it.
struct AwayDot: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Palette.muted)
            .frame(width: size, height: size)
            .accessibilityLabel("Away from its pinned page")
    }
}
```

- [ ] **Step 2: The dot on the sidebar's squares**

In `PinSquare.body`, find:

```swift
        .contentShape(RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous))
```

and insert directly **before** it:

```swift
        .overlay(alignment: .bottom) {
            if tab.away { AwayDot(size: max(3, scale * 4 / 34)).offset(y: -scale * 3 / 34) }
        }
```

- [ ] **Step 3: The dot on the tab bar's squares**

In `TabBar.swift`, in the pinned branch of `TabPill.body`, find:

```swift
                .frame(width: 16, height: 16)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .frame(width: span)
```

and replace it with:

```swift
                .frame(width: 16, height: 16)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .frame(width: span)
                .overlay(alignment: .bottom) {
                    if tab.away { AwayDot(size: 4).offset(y: -2) }
                }
```

- [ ] **Step 4: The right-click menu**

In `TabMenu.body` (`TabBar.swift`), replace:

```swift
        if tab.pin == nil {
            Button("Pin") { browser.pin(tab) }
                .disabled(tab.isBlank)
        } else {
            Button("Change Letter") { browser.editLetter(tab) }
            Button("Unpin") { browser.unpin(tab) }
        }
```

with:

```swift
        if tab.pin == nil {
            Button("Add to Favorites") { browser.pin(tab) }
                .disabled(tab.isBlank)
        } else {
            Button("Change Letter") { browser.editLetter(tab) }
            Button("Remove from Favorites") { browser.unpin(tab) }
            Divider()
            Button("Back to Pinned Page") { browser.goHome(tab) }
                .disabled(!tab.away)
            Button("Set Pinned Page to This Page") { browser.setHome(tab) }
                .disabled(!tab.away || tab.address == nil)
        }
```

- [ ] **Step 5: The Tabs menu**

The menu bar observes `browser` only, and `tab.away` changes with the tab's own properties. So the kept-tab items go in a small view that observes the tab.

At the end of `TabBar.swift`, after `TabMenu`, add:

```swift

/// The Tabs menu's lines for the tab on screen: watched as a tab, so Back to
/// Pinned Page lights up the moment the page wanders off.
struct KeptTabCommands: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab

    var body: some View {
        if tab.pin == nil {
            Button("Add to Favorites") { browser.pin(tab) }
                .disabled(tab.isBlank)
        } else {
            Button("Change Letter") { browser.editLetter(tab) }
            Button("Remove from Favorites") { browser.unpin(tab) }
            Button("Back to Pinned Page") { browser.goHome(tab) }
                .disabled(!tab.away)
            Button("Set Pinned Page to This Page") { browser.setHome(tab) }
                .disabled(!tab.away || tab.address == nil)
        }
    }
}
```

Then in `App.swift`, replace:

```swift
                if let tab = browser.active {
                    if tab.pin == nil {
                        Button("Pin Tab") { browser.pin(tab) }
                            .disabled(tab.isBlank)
                    } else {
                        Button("Change Letter") { browser.editLetter(tab) }
                        Button("Unpin Tab") { browser.unpin(tab) }
                    }
                }
```

with:

```swift
                if let tab = browser.active {
                    KeptTabCommands(browser: browser, tab: tab)
                }
```

- [ ] **Step 6: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then `✔ Test run with 18 tests in 4 suites passed`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Search/Side.swift Sources/Search/TabBar.swift Sources/Search/App.swift
git commit -m "A favorite that has left its page shows a dot, and its menu takes it back or makes this its page"
```

---

### Task 6: Bench commands, the end-to-end check, the changelog and the PR

**Files:**
- Modify: `Sources/Search/Bench.swift`: `describe` (search for `private func describe(_ tab: Tab)`), plus new cases before `case "text":`.
- Modify: `bench`: the docstring usage lines, the request building after the `("text", "close", "sleep", "select")` branch, and the `tabs` printing.
- Modify: `CHANGELOG.md`, under `## Unreleased` › `### Added`.

**Interfaces:**
- Consumes: everything above.
- Produces: `./bench --test keep ID favorites|off` and `./bench --test home ID [go|set]`, both answering with `describe(tab)`. It now includes `pin`, `shelf`, `home`, `away` and `folder`.

- [ ] **Step 1: `describe` reports the shelf**

In `Bench.swift`, inside `describe(_:)`, directly after `"muted": tab.muted,`, add:

```swift
            "pin": tab.pin ?? "",
            "shelf": tab.pin == nil ? "" : tab.shelf.rawValue,
            "home": tab.home?.absoluteString ?? "",
            "away": tab.away,
            "folder": tab.folder?.uuidString ?? "",
```

- [ ] **Step 2: The `keep` and `home` verbs**

In `Bench.swift`, directly before `case "text":`, insert:

```swift
        case "keep":
            // A tab made a favorite or let go, as its menu would. Changing
            // what is kept changes your row: only on a SEARCH_PROBE run.
            guard Store.testing else { answer(["error": "keep only works on a --test run — it changes your tabs"]); return }
            guard let tab = find(request, in: browser) else { answer(missing(request)); return }
            switch request["as"] as? String ?? "" {
            case "favorites": browser.pin(tab)
            case "off": browser.unpin(tab)
            default: answer(["error": "keep needs favorites or off"]); return
            }
            answer(describe(tab))

        case "home":
            // A kept tab's page: where it is, back to it, or this page as it.
            guard Store.testing else { answer(["error": "home only works on a --test run — it changes your tabs"]); return }
            guard let tab = find(request, in: browser) else { answer(missing(request)); return }
            switch request["what"] as? String ?? "" {
            case "go": browser.goHome(tab)
            case "set": browser.setHome(tab)
            default: break
            }
            answer(describe(tab))

```

- [ ] **Step 3: The client**

In `bench`, directly after the branch:

```python
    elif verb in ("text", "close", "sleep", "select"):
        if len(args) != 1: sys.exit(f"usage: bench {verb} ID")
        request["id"] = args[0]
```

insert:

```python
    elif verb == "keep":
        if len(args) != 2 or args[1] not in ("favorites", "off"): sys.exit("usage: bench keep ID favorites|off")
        request["id"], request["as"] = args
    elif verb == "home":
        if len(args) not in (1, 2) or (len(args) == 2 and args[1] not in ("go", "set")): sys.exit("usage: bench home ID [go|set]")
        request["id"] = args[0]
        if len(args) == 2: request["what"] = args[1]
```

In the `tabs` printing branch, replace:

```python
            print(f"{mark} {tab['id']}  {tab.get('title') or '—'}  {tab.get('url')}{state}")
```

with:

```python
            kept = {"favorites": "FAV ", "pins": "PIN "}.get(tab.get("shelf"), "")
            away = " (away from " + tab.get("home") + ")" if tab.get("away") else ""
            print(f"{mark} {tab['id']}  {kept}{tab.get('title') or '—'}  {tab.get('url')}{state}{away}")
```

In the docstring, after the line that starts `    ./bench close ID | all`, add:

```
    ./bench keep ID favorites|off      a tab made a favorite, or let go — --test runs only
    ./bench home ID [go|set]           a kept tab's page: where it is, back to it, or this page as it — --test runs only
```

- [ ] **Step 4: Build, test, and start a test run with a redirecting server**

```bash
swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3
```

Expected: `Build complete!`, then all tests pass.

Write a local server that stands in for a site whose front door starts redirecting. `/home` serves a page on the first visit and redirects to `/inbox` from the second visit on.

```bash
cat > /tmp/shelves-server.py <<'EOF'
import http.server
visits = {"home": 0}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/home":
            visits["home"] += 1
            if visits["home"] > 1:
                self.send_response(302); self.send_header("Location", "/inbox"); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers()
        self.wfile.write(f"<title>{self.path}</title><a id=out href='/elsewhere'>out</a>".encode())
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 8765), H).serve_forever()
EOF
nohup python3 /tmp/shelves-server.py >/dev/null 2>&1 & echo $! > /tmp/shelves-server.pid
```

Launch the debug build. Running it from `.build/` makes it a test run in the "Search (test)" world, with the bench on.

```bash
nohup .build/debug/Search >/tmp/search-test.log 2>&1 &
sleep 3 && ./bench --test tabs
```

Expected: a tab listing with no error.

- [ ] **Step 5: Check the away state, ⌘W, and a redirecting home**

```bash
ID=$(./bench --test open http://127.0.0.1:8765/home) && ./bench --test wait $ID
./bench --test keep $ID favorites
```

Expected: `"shelf": "favorites"`, `"home": "http://127.0.0.1:8765/home"`, `"away": false`. This was the first visit, so there was no redirect.

```bash
./bench --test go $ID http://127.0.0.1:8765/elsewhere && ./bench --test wait $ID
./bench --test home $ID
```

Expected: `"away": true`.

```bash
./bench --test close $ID
./bench --test tabs
```

Expected: the tab is still listed as `FAV`, marked `z` (asleep), with URL `http://127.0.0.1:8765/home` and no `(away from …)`. A kept tab is put down at its home, not closed.

```bash
./bench --test select $ID && ./bench --test wait $ID
./bench --test home $ID
```

Expected: `"url": "http://127.0.0.1:8765/inbox"` and `"away": false`. It woke at its home, `/home` redirected (second visit), and the place it landed counts as home.

```bash
./bench --test go $ID http://127.0.0.1:8765/elsewhere && ./bench --test wait $ID
./bench --test home $ID go && ./bench --test wait $ID
./bench --test home $ID
```

Expected: `"url": "http://127.0.0.1:8765/inbox"` and `"away": false`. Back to Pinned Page went through the redirect and is home.

```bash
./bench --test go $ID http://127.0.0.1:8765/elsewhere && ./bench --test wait $ID
./bench --test home $ID set
```

Expected: `"home": "http://127.0.0.1:8765/elsewhere"` and `"away": false`.

- [ ] **Step 6: Check that an old session migrates**

```bash
pkill -f ".build/debug/Search"; sleep 1
D="$HOME/Library/Application Support/Search (test)"
cp "$D/session.json" "$D/session.json.before-shelves" 2>/dev/null || true
cat > "$D/session.json" <<'EOF'
{"tabs":[
  {"url":"http://127.0.0.1:8765/inbox","title":"Inbox","pin":"I"},
  {"url":"http://127.0.0.1:8765/a","title":"A"},
  {"url":"http://127.0.0.1:8765/cal","title":"Cal","pin":"C"}
],"active":1}
EOF
nohup .build/debug/Search >/tmp/search-test.log 2>&1 &
sleep 3 && ./bench --test tabs
```

Expected, in this order:
1. `FAV Inbox`
2. `FAV Cal`
3. `A` (active, `●`)

None is away. Then force a save and read the file back. Running `keep … favorites` on a tab that is already a favorite writes the session immediately:

```bash
FAV=$(./bench --test tabs | awk '/FAV Inbox/ {print $2}')
./bench --test keep $FAV favorites >/dev/null
python3 -m json.tool "$D/session.json"
```

Expected: both kept entries carry `"shelf": "favorites"` and a `"home"` equal to their `url`, with no `folders` key.

- [ ] **Step 7: Check that switching spaces keeps shelves**

```bash
./bench --test ui spaces on
./bench --test space new Other && ./bench --test space go 1
./bench --test tabs
```

Expected: the same two `FAV` tabs with the same URLs, and no `(away …)`. Then clean up:

```bash
./bench --test ui spaces off
pkill -f ".build/debug/Search"; kill "$(cat /tmp/shelves-server.pid)"
[ -f "$D/session.json.before-shelves" ] && mv "$D/session.json.before-shelves" "$D/session.json"
```

- [ ] **Step 8: Look at it**

Run `./build.sh`, then `open -n --env SEARCH_PROBE=1 build/Search.app`. By hand:
1. Right-click a tab: "Add to Favorites".
2. Follow a link from it, and a dot appears under its square, in both the sidebar and the top bar (⇧⌘S).
3. Right-click it: "Back to Pinned Page" is enabled, and clicking it clears the dot. Check the same item in the Tabs menu.
4. ⌘W on it while away, then click it again: it opens at its home.

Take `./bench --test column /tmp/shelves-column.png` while the dot is showing.

Expected: `./build.sh` finishes without errors, and all four behave as described.

- [ ] **Step 9: Changelog**

In `CHANGELOG.md`, under `## Unreleased` › `### Added`, add a line at the top of the list:

```markdown
- Pinned tabs are favorites now, and each remembers the page it was pinned at. Wander off it and a dot shows under its square; ⌘W puts it down back at that page, and its menu has Back to Pinned Page and Set Pinned Page to This Page. A redirect on the way home still counts as home. The groundwork for pinned rows and folders, as in Arc.
```

- [ ] **Step 10: Commit**

```bash
git add Sources/Search/Bench.swift bench CHANGELOG.md
git commit -m "The bench can favorite a tab and send it home; the changelog says what changed"
```

- [ ] **Step 11: Push and open the PR against the fork**

```bash
git push -u origin sidebar-shelves
gh pr create --repo Richard-DEPIERRE/Search --base main --head sidebar-shelves \
  --title "Favorites that remember their page (shelves, part 1 of 3)" \
  --body "$(cat <<'EOF'
Part 1 of the sidebar work in docs/superpowers/specs/2026-09-25-sidebar-favorites-pins-folders-design.md.

- Today's pins become favorites and look the same. Each remembers the page it was kept at.
- A favorite that has left its page shows a dot; ⌘W puts it down back at its page; Back to Pinned Page / Set Pinned Page to This Page in its menus.
- A redirect on the way home counts as home.
- The session keeps shelf, home and folder; an old session.json reads as favorites at their saved page.
- New pure rules in Shelves.swift and a Swift Testing target (`swift test`).
- Bench: `keep ID favorites|off`, `home ID [go|set]`.

Checked: swift build, swift test, ./build.sh; on a test run, a redirecting home, away and back, ⌘W while away, an old session file, and a trip through another space.

Next: pinned rows (part 2), then folders (part 3).
EOF
)"
```

Expected: `gh` prints the URL of a PR on `github.com/Richard-DEPIERRE/Search`, **not** on `driceroland/Search`.
