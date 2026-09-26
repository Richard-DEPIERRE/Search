# Split view — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show two to four tabs side by side, as full-height columns with draggable dividers. ⌃⇧= adds a pane. A split is a lasting group, saved with the session. The focused pane is the active tab.

**Architecture:**
- A pure `Splits.swift` holds `Split` and every rule: adding, removing, resizing, evening, tidying, and saving and restoring by position.
- `Browser` keeps `splits: [Split]` per space, beside the unchanged flat `tabs` list.
- The page area draws a `SplitStage` when the active tab is in a split. The stage is one `Page` per member, with dividers between them; a focus ring and the page overlays sit on the focused pane.
- A local mouse-down monitor focuses the pane that was clicked.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftPM, AppKit + SwiftUI + WebKit, Swift Testing, and `./bench`.

**Spec:** `docs/superpowers/specs/2026-09-26-split-view-design.md`. Branch `split-view`, stacked on `peek-links` (#4). Its PR's base is `peek-links`.

## Global Constraints

- macOS 14 or later. No dependencies beyond what Apple ships. Swift language mode v5.
- **Panes:** 2–4 per split, side by side, full height. `Splits.minimum = 0.12` is the smallest a pane's width fraction can be. Dividers are 6pt wide (`SplitStage.gap`).
- **Membership:** a tab is in at most one split. Any tab can be a member: favorites, pins or today's tabs. The flat `tabs` list and its order invariant don't change.
- **Focus:** the focused pane is `browser.activeID`. Focusing a pane by clicking it sets `activeID` without running `select()`.
- **Keys** are matched by key code with exactly ⌃⇧ held:
  - ⌃⇧= (24) is New Split Pane;
  - ⌃⇧- (27) is Remove from Split;
  - ⌃⇧] (30) and ⌃⇧[ (33) are the next and previous pane.
- **Session:** the optional `splits` key saves positions in the written list plus widths. It is read leniently, like `folders`.
- **Pure rules:** `Splits.swift` imports Foundation only, and every rule gets a test.
- **Voice:** comments are plain sentences explaining *why*. No attribution lines. Never run `./ideas`. One CHANGELOG line under `## Unreleased` › `### Added`.
- **Testing safety:** checks drive only the test instance (`.build/debug/Search`, `./bench --test`). Never touch `~/Library/Application Support/Search/`.

## Review Focus

1. **⌘W on a pane.** The tab leaves its split and focus lands on its neighbour: no blank page area, and no jump to an unrelated tab. Pinned by Task 3's `close` change and Task 6, Step 5.
2. **A click in a pane.** It focuses that pane, and the page still gets the click (links, text fields). Pinned by Task 4's monitor and Task 6, Step 4.
3. **A relaunch with a split.** The split comes back with its widths. A broken entry costs only itself. Pinned by `SplitsTests` and `SessionTests` in Tasks 1–2, and Task 6, Step 7.
4. **Tabs that close outside our commands** (an extension, `window.close()`, Close Other Tabs). They leave their split cleanly: no pane shows a closed tab. Pinned by the tidying in `tabs`' `didSet` (Task 2) and Task 6, Step 6.
5. **The page overlays in a split.** The find bar, the link bubble and account suggestions sit over the focused pane, not across all panes. Pinned by Task 4's `PageOverlays` and the owner's manual pass.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/Search/Splits.swift` | **Create** | `Split`, `SavedSplit`, and `Splits` (the rules). Pure. |
| `Tests/SearchTests/SplitsTests.swift` | **Create** | Tests for the rules. |
| `Sources/Search/Session.swift` | Modify | `Shape.splits: [SavedSplit]?`, decoded leniently. |
| `Tests/SearchTests/SessionTests.swift` | Modify | Lenient `splits` tests. |
| `Sources/Search/Browser.swift` | Modify | `splits`, `activeSplit`, tidying on `tabs` changes, writing and restoring; the commands `newSplitPane`, `removeFromSplit`, `addToSplit`, `focusPane`, `stepPane`, `resizeSplit`, `evenSplit`; `close` lands on the neighbouring pane; `select` wakes the split. |
| `Sources/Search/Spaces.swift` | Modify | `Parked.splits`, carried by `enter`. |
| `Sources/Search/Sleep.swift` | Modify | The split's members on screen stay awake. |
| `Sources/Search/Split.swift` | **Create** | `SplitStage`, `SplitDivider`, `PageOverlays`, `SplitMark`, and the pane-focus monitor. |
| `Sources/Search/App.swift` | Modify | `stage` uses `SplitStage` and `PageOverlays`; `take()` gets the four keys; the Tabs menu gets its items. |
| `Sources/Search/TabBar.swift` | Modify | `TabMenu` gets Add to / Remove from Split; `TabPill` gets the split mark. |
| `Sources/Search/Side.swift` | Modify | `SideRow` and `PinSquare` get the split mark and the lighter on-screen ground. |
| `Sources/Search/Bench.swift`, `bench` | Modify | The `split` verb. |
| `CHANGELOG.md` | Modify | One line. |

---

### Task 1: The split rules, tested

**Files:**
- Create: `Sources/Search/Splits.swift`
- Create: `Tests/SearchTests/SplitsTests.swift`

**Interfaces:**
- Produces:
  - `struct Split: Codable, Identifiable, Equatable { var id: UUID; var tabs: [UUID]; var widths: [Double] }`
  - `struct SavedSplit: Codable, Equatable { var tabs: [Int]; var widths: [Double] }`
  - `enum Splits`, with:
    - `static let most = 4` and `static let minimum = 0.12`
    - `split(containing:in:) -> Split?`
    - `adding(_:beside:to:) -> [Split]?`
    - `removing(_:from:) -> [Split]`
    - `resizing(_:divider:to:in:) -> [Split]`
    - `evened(_:in:) -> [Split]`
    - `tidy(_:existing:) -> [Split]`
    - `saved(_:order:) -> [SavedSplit]`
    - `restored(_:order: [UUID?]) -> [Split]`
    - `neighbour(of:in:) -> UUID?`, which returns the left neighbour, or the right one if the tab is first

- [ ] **Step 1: Write the failing tests**

Create `Tests/SearchTests/SplitsTests.swift`:

```swift
import Foundation
import Testing
@testable import Search

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let splitID = UUID(uuidString: "5B000000-0000-0000-0000-000000000001")!
private func split(_ tabs: [Int], _ widths: [Double]) -> Split { Split(id: splitID, tabs: tabs.map(id), widths: widths) }
private func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 0.0001 } }

@Suite struct SplitAddTests {
    @Test func besideATabInNoSplitMakesAPairAtHalves() {
        let out = Splits.adding(id(2), beside: id(1), to: [])!
        #expect(out.count == 1)
        #expect(out[0].tabs == [id(1), id(2)])
        #expect(near(out[0].widths, [0.5, 0.5]))
    }

    @Test func besideAPaneGoesToItsRightAtAnEvenShare() {
        let out = Splits.adding(id(3), beside: id(1), to: [split([1, 2], [0.6, 0.4])])!
        #expect(out[0].tabs == [id(1), id(3), id(2)])
        #expect(near(out[0].widths, [0.4, 1.0 / 3, 0.4 * 2 / 3]))
    }

    @Test func aFullSplitTakesNoMore() {
        #expect(Splits.adding(id(5), beside: id(1), to: [split([1, 2, 3, 4], [0.25, 0.25, 0.25, 0.25])]) == nil)
    }

    @Test func aTabAlreadyInAnotherSplitLeavesItFirst() {
        let other = Split(id: UUID(), tabs: [id(8), id(9)], widths: [0.5, 0.5])
        let out = Splits.adding(id(9), beside: id(1), to: [other])!
        #expect(out.count == 1)
        #expect(out[0].tabs == [id(1), id(9)])
    }
}

@Suite struct SplitRemoveTests {
    @Test func aPanesWidthGoesToItsNeighbours() {
        let out = Splits.removing(id(2), from: [split([1, 2, 3], [0.25, 0.5, 0.25])])
        #expect(out[0].tabs == [id(1), id(3)])
        #expect(near(out[0].widths, [0.5, 0.5]))
    }

    @Test func aSplitLeftWithOnePaneEnds() {
        #expect(Splits.removing(id(1), from: [split([1, 2], [0.5, 0.5])]).isEmpty)
    }

    @Test func aTabInNoSplitChangesNothing() {
        let splits = [split([1, 2], [0.5, 0.5])]
        #expect(Splits.removing(id(7), from: splits) == splits)
    }
}

@Suite struct SplitResizeTests {
    @Test func aDividerMovesOnlyItsTwoPanes() {
        let out = Splits.resizing(splitID, divider: 0, to: 0.3, in: [split([1, 2, 3], [0.4, 0.3, 0.3])])
        #expect(near(out[0].widths, [0.3, 0.4, 0.3]))
    }

    @Test func noPaneGoesBelowTheMinimum() {
        let out = Splits.resizing(splitID, divider: 0, to: 0.01, in: [split([1, 2], [0.5, 0.5])])
        #expect(near(out[0].widths, [Splits.minimum, 1 - Splits.minimum]))
    }

    @Test func evenedGivesEveryPaneTheSame() {
        let out = Splits.evened(splitID, in: [split([1, 2, 3], [0.6, 0.2, 0.2])])
        #expect(near(out[0].widths, [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }
}

@Suite struct SplitTidyTests {
    @Test func aClosedTabLeavesAndAPairOfOneEnds() {
        let out = Splits.tidy([split([1, 2], [0.5, 0.5])], existing: [id(1)])
        #expect(out.isEmpty)
    }

    @Test func aTabIsKeptInItsFirstSplitOnly() {
        let second = Split(id: UUID(), tabs: [id(2), id(3)], widths: [0.5, 0.5])
        let out = Splits.tidy([split([1, 2], [0.5, 0.5]), second], existing: [id(1), id(2), id(3)])
        #expect(out.count == 1)
        #expect(out[0].tabs == [id(1), id(2)])
    }

    @Test func brokenWidthsAreEvened() {
        let out = Splits.tidy([split([1, 2, 3], [0.5, .nan])], existing: [id(1), id(2), id(3)])
        #expect(near(out[0].widths, [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func moreThanFourKeepsTheFirstFour() {
        let out = Splits.tidy([split([1, 2, 3, 4, 5], [0.2, 0.2, 0.2, 0.2, 0.2])], existing: Set((1...5).map(id)))
        #expect(out[0].tabs == [id(1), id(2), id(3), id(4)])
        #expect(near(out[0].widths, [0.25, 0.25, 0.25, 0.25]))
    }

    @Test func widthsThatDontAddUpAreScaled() {
        let out = Splits.tidy([split([1, 2], [1, 3])], existing: [id(1), id(2)])
        #expect(near(out[0].widths, [0.25, 0.75]))
    }
}

@Suite struct SplitSaveTests {
    @Test func savedAsPositionsInTheWrittenList() {
        let saved = Splits.saved([split([2, 4], [0.3, 0.7])], order: [id(1), id(2), id(3), id(4)])
        #expect(saved == [SavedSplit(tabs: [1, 3], widths: [0.3, 0.7])])
    }

    @Test func aTabThatIsNotWrittenDropsOut() {
        let saved = Splits.saved([split([2, 9, 4], [0.2, 0.3, 0.5])], order: [id(1), id(2), id(4)])
        #expect(saved.count == 1)
        #expect(saved[0].tabs == [1, 2])
        #expect(near(saved[0].widths, [0.2 / 0.7, 0.5 / 0.7]))
    }

    @Test func restoredFromPositionsAndMissingOnesDrop() {
        let out = Splits.restored([SavedSplit(tabs: [0, 2], widths: [0.4, 0.6]), SavedSplit(tabs: [1, 7], widths: [0.5, 0.5])],
                                  order: [id(1), nil, id(3)])
        #expect(out.count == 1)
        #expect(out[0].tabs == [id(1), id(3)])
        #expect(near(out[0].widths, [0.4, 0.6]))
    }

    @Test func theNeighbourIsToTheLeftOrElseTheRight() {
        let splits = [split([1, 2, 3], [0.3, 0.4, 0.3])]
        #expect(Splits.neighbour(of: id(2), in: splits) == id(1))
        #expect(Splits.neighbour(of: id(1), in: splits) == id(2))
        #expect(Splits.neighbour(of: id(9), in: splits) == nil)
    }
}
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `swift test 2>&1 | grep -E "error:|Test run" | head -5`
Expected: a compile failure, `cannot find 'Split' in scope`.

- [ ] **Step 3: Write `Splits.swift`**

Create `Sources/Search/Splits.swift`:

```swift
import Foundation

// Split view: two to four tabs side by side, each a full-height column. A
// split is a lasting group beside the row of tabs — the row itself doesn't
// change — and these are its rules. Nothing here knows about pages or views,
// so the rules are tested on their own (Tests/SearchTests).

/// Tabs shown side by side, left to right, each as wide as its fraction.
struct Split: Codable, Identifiable, Equatable {
    var id: UUID
    var tabs: [UUID]
    var widths: [Double]
}

/// A split as the session keeps it: tab ids aren't saved, so its tabs are
/// their places in the list the session wrote.
struct SavedSplit: Codable, Equatable {
    var tabs: [Int]
    var widths: [Double]
}

enum Splits {
    /// Four columns is as many as a Mac screen reads side by side.
    static let most = 4
    /// No pane narrower than this share, however a divider is dragged.
    static let minimum = 0.12

    static func split(containing tab: UUID, in splits: [Split]) -> Split? {
        splits.first { $0.tabs.contains(tab) }
    }

    /// A tab added as a pane right of `beside`: into its split at an even
    /// share, the others giving up theirs in proportion, or as a new pair at
    /// halves. Nil when that split is full. A tab in another split leaves it.
    static func adding(_ tab: UUID, beside: UUID, to splits: [Split]) -> [Split]? {
        var splits = removing(tab, from: splits)
        guard let s = splits.firstIndex(where: { $0.tabs.contains(beside) }) else {
            return splits + [Split(id: UUID(), tabs: [beside, tab], widths: [0.5, 0.5])]
        }
        guard splits[s].tabs.count < most, let at = splits[s].tabs.firstIndex(of: beside) else { return nil }
        let n = Double(splits[s].tabs.count + 1)
        splits[s].widths = splits[s].widths.map { $0 * (n - 1) / n }
        splits[s].tabs.insert(tab, at: at + 1)
        splits[s].widths.insert(1 / n, at: at + 1)
        return splits
    }

    /// A pane taken out: its width goes to the panes beside it, in proportion
    /// to theirs. A split left with one pane is no split.
    static func removing(_ tab: UUID, from splits: [Split]) -> [Split] {
        splits.compactMap { split in
            guard let at = split.tabs.firstIndex(of: tab) else { return split }
            var split = split
            let freed = split.widths.indices.contains(at) ? split.widths[at] : 0
            split.tabs.remove(at: at)
            if split.widths.indices.contains(at) { split.widths.remove(at: at) }
            guard split.tabs.count >= 2, split.widths.count == split.tabs.count else {
                return split.tabs.count >= 2 ? tidy([split], existing: Set(split.tabs)).first : nil
            }
            let near = [at - 1, at].filter { split.widths.indices.contains($0) }
            let share = near.reduce(0) { $0 + split.widths[$1] }
            for i in near { split.widths[i] += share > 0 ? freed * split.widths[i] / share : freed / Double(near.count) }
            return split
        }
    }

    /// A divider dragged to `fraction` of the split's width: only the two
    /// panes either side of it change, and neither below the minimum.
    static func resizing(_ id: UUID, divider: Int, to fraction: Double, in splits: [Split]) -> [Split] {
        splits.map { split in
            guard split.id == id, divider >= 0, split.widths.indices.contains(divider + 1) else { return split }
            var split = split
            let before = split.widths[..<divider].reduce(0, +)
            let both = split.widths[divider] + split.widths[divider + 1]
            let at = min(max(fraction, before + minimum), before + both - minimum)
            split.widths[divider] = at - before
            split.widths[divider + 1] = both - (at - before)
            return split
        }
    }

    /// Every pane the same width: a double-click on a divider.
    static func evened(_ id: UUID, in splits: [Split]) -> [Split] {
        splits.map { split in
            guard split.id == id else { return split }
            var split = split
            split.widths = Array(repeating: 1 / Double(split.tabs.count), count: split.tabs.count)
            return split
        }
    }

    /// The splits as they can be shown: only tabs that exist, each in one
    /// split, two to four to a split, widths that add up. A hand-edited or
    /// cut-short session comes back whole rather than as a page area that
    /// doesn't add up.
    static func tidy(_ splits: [Split], existing: Set<UUID>) -> [Split] {
        var seen = Set<UUID>()
        return splits.compactMap { split in
            var split = split
            var kept: [(UUID, Double)] = []
            let widthsFit = split.widths.count == split.tabs.count && split.widths.allSatisfy { $0.isFinite && $0 > 0 }
            for (i, tab) in split.tabs.enumerated() where existing.contains(tab) && !seen.contains(tab) && kept.count < most {
                seen.insert(tab)
                kept.append((tab, widthsFit ? split.widths[i] : 1))
            }
            guard kept.count >= 2 else { return nil }
            let total = kept.reduce(0) { $0 + $1.1 }
            split.tabs = kept.map(\.0)
            split.widths = kept.map { max(minimum, $0.1 / total) }
            let sum = split.widths.reduce(0, +)
            split.widths = split.widths.map { $0 / sum }
            return split
        }
    }

    /// The pane focus goes to when `tab` leaves: the one to its left, or to
    /// its right when it was first.
    static func neighbour(of tab: UUID, in splits: [Split]) -> UUID? {
        guard let split = split(containing: tab, in: splits), let at = split.tabs.firstIndex(of: tab) else { return nil }
        return at > 0 ? split.tabs[at - 1] : split.tabs.count > 1 ? split.tabs[1] : nil
    }

    /// The splits as places in the list the session writes. A tab it doesn't
    /// write drops out, its share going to the rest.
    static func saved(_ splits: [Split], order: [UUID]) -> [SavedSplit] {
        let place = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return splits.compactMap { split in
            let kept = zip(split.tabs, split.widths).compactMap { tab, width in place[tab].map { ($0, width) } }
            guard kept.count >= 2 else { return nil }
            let total = kept.reduce(0) { $0 + $1.1 }
            return SavedSplit(tabs: kept.map(\.0), widths: kept.map { total > 0 ? $0.1 / total : 1 / Double(kept.count) })
        }
    }

    /// Saved splits back onto the tabs the session brought back. `order` has
    /// nil where an entry brought no tab back; places that land there drop.
    static func restored(_ saved: [SavedSplit], order: [UUID?]) -> [Split] {
        let splits = saved.map { saved in
            let pairs = zip(saved.tabs, saved.widths).compactMap { place, width -> (UUID, Double)? in
                guard order.indices.contains(place), let tab = order[place] else { return nil }
                return (tab, width)
            }
            return Split(id: UUID(), tabs: pairs.map(\.0), widths: pairs.map(\.1))
        }
        return tidy(splits, existing: Set(order.compactMap { $0 }))
    }
}
```

- [ ] **Step 4: Run the tests and check they pass**

Run: `swift test 2>&1 | tail -1`
Expected: `✔ Test run with 107 tests in 21 suites passed`. That is 88 before, plus 19 new tests in 5 new suites. If Swift Testing counts suites differently, check that every test passes and 19 were added.

- [ ] **Step 5: Commit**

```bash
git add Sources/Search/Splits.swift Tests/SearchTests/SplitsTests.swift
git commit -m "The rules for split view: adding, removing, resizing and keeping splits, with tests"
```

---

### Task 2: Splits in the session and in each space

**Files:**
- Modify: `Sources/Search/Session.swift`, the `Shape` struct and its lenient `init(from:)` extension.
- Modify: `Tests/SearchTests/SessionTests.swift`
- Modify: `Sources/Search/Browser.swift`:
  - `tabs` (line 11);
  - `writeSession`, `restoreSession`'s loop and end, `loadRow`'s loop and return, `showRow`;
  - a new `splits` block after the folders block.
- Modify: `Sources/Search/Spaces.swift`: `Parked` and `enter(_:)`.

**Interfaces:**
- Consumes: `Splits.saved`, `Splits.restored`, `Splits.tidy` and `Splits.split(containing:in:)` (Task 1).
- Produces (used by Tasks 3–6):
  - `Session.Shape.splits: [SavedSplit]?`
  - `@Published var Browser.splits: [Split]`
  - `var Browser.activeSplit: Split?`
  - `func Browser.split(of tab: Tab) -> Split?`
  - `Parked.splits: [Split]`, which defaults to `[]`
  - `showRow(_:active:folders:splits:)`

- [ ] **Step 1: Write the failing session tests**

Append inside `@Suite struct SessionTests` in `Tests/SearchTests/SessionTests.swift`:

```swift

    @Test func splitsAreReadBack() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A"},{"url":"https://b.com/","title":"B"}],"active":0,
         "splits":[{"tabs":[0,1],"widths":[0.4,0.6]}]}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.splits == [SavedSplit(tabs: [0, 1], widths: [0.4, 0.6])])
    }

    @Test func aSplitThatWontReadIsDroppedNotTheSession() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A"}],"active":0,
         "splits":[{"tabs":[0,1],"widths":[0.5,0.5]},{"tabs":"nonsense"}]}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.tabs.count == 1)
        #expect(shape.splits?.count == 1)
    }
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `swift test 2>&1 | grep -E "error:|Test run" | head -3`
Expected: a compile failure, `value of type 'Session.Shape' has no member 'splits'`.

- [ ] **Step 3: The session key**

In `Session.swift`:
- In `struct Shape`, after `var folders: [Folder]?`, add:
  ```swift
      /// This space's splits, as places in `tabs` (see Splits.swift). Absent
      /// from sessions without any.
      var splits: [SavedSplit]?
  ```
- In the lenient `init(from:)` extension, after the `folders = …` line, add:
  ```swift
          splits = (try? container.decodeIfPresent([Lossy<SavedSplit>].self, forKey: .splits))?.compactMap(\.value)
  ```

Run `swift test 2>&1 | tail -1`. Expected: 109 tests pass.

- [ ] **Step 4: The browser's splits**

In `Browser.swift`, directly after the line `@Published var folders: [Folder] = []`, add:

```swift

    /// This space's splits (see Splits.swift): tabs shown side by side. Saved
    /// with its tabs, and parked with them while another space is on screen.
    @Published var splits: [Split] = []

    /// The split on screen: the one the tab you are on belongs to.
    var activeSplit: Split? {
        guard let activeID else { return nil }
        return Splits.split(containing: activeID, in: splits)
    }

    func split(of tab: Tab) -> Split? {
        Splits.split(containing: tab.id, in: splits)
    }
```

Change the declaration `@Published private(set) var tabs: [Tab] = []` (line 11) to:

```swift
    @Published private(set) var tabs: [Tab] = [] {
        // However a tab goes — closed, an extension's doing, a page closing
        // itself — it leaves its split, and a split left with one pane ends.
        didSet {
            let tidied = Splits.tidy(splits, existing: Set(tabs.map(\.id)))
            if tidied != splits { splits = tidied }
        }
    }
```

If `tabs` already has a `didSet`, put these lines inside it.

- [ ] **Step 5: Written and restored**

In `writeSession`, the entries come from `tabs.compactMap { tab in … }`. Also collect the ids of the tabs actually written:
- Keep a local `var written: [UUID] = []` before the call.
- In the closure, append `tab.id` just before it returns an entry. Do this at the single `return Session.Entry(…)`.
- Leave the entry fields exactly as they are.
- After the `folders: …` argument, add:
  ```swift
                  splits: {
                      let saved = Splits.saved(splits, order: written)
                      return saved.isEmpty ? nil : saved
                  }()
  ```

Swift evaluates the `tabs:` argument before `splits:`, so `written` is filled by then. If the compiler rejects mutating a local from inside the closure in an argument list, first build the entries into a local `let entries = …` above the `.init`, and pass `tabs: entries`.

In `restoreSession`:
- Before the `for entry in saved.tabs {` loop, add `var order: [UUID?] = []`.
- In the loop, the guard `guard let url = URL(string: entry.url) else { continue }` becomes `guard let url = URL(string: entry.url) else { order.append(nil); continue }`.
- Right after `tabs.append(tab)`, add `order.append(tab.id)`.
- After `folders = saved.folders ?? []`, add:
  ```swift
          splits = Splits.restored(saved.splits ?? [], order: order)
  ```

Do the same in `loadRow`, with its own `order`, its own `continue` guard and its `row.append(tab)`. Its return becomes:

```swift
        return Parked(tabs: tidy, active: active, folders: folders, splits: Splits.restored(saved.splits ?? [], order: order))
```

Change `showRow` to:

```swift
    func showRow(_ row: [Tab], active: Tab.ID?, folders: [Folder] = [], splits: [Split] = []) {
        self.splits = splits
        tabs = row
        self.folders = folders
        activeID = active ?? row.first?.id
    }
```

`splits` is set before `tabs`, so `tabs`' `didSet` tidies against the new row.

- [ ] **Step 6: Spaces park their splits**

In `Spaces.swift`:
- `struct Parked` gains `var splits: [Split] = []`, with a one-line comment.
- In `enter(_:)`, the parking line becomes `parked[spaceID] = Parked(tabs: tabs, active: activeID, folders: folders, splits: splits)`.
- The return line becomes `showRow(back.tabs, active: back.active, folders: back.folders, splits: back.splits)`.

- [ ] **Step 7: Build and test**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -1`
Expected: `Build complete!`, then 109 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/Search/Session.swift Tests/SearchTests/SessionTests.swift Sources/Search/Browser.swift Sources/Search/Spaces.swift
git commit -m "Each space keeps its splits, saves them with its tabs and parks them with them"
```

---

### Task 3: The split commands, closing, sleeping, keys and menus

**Files:**
- Modify: `Sources/Search/Browser.swift`: a new block after `split(of:)`; `close(_:)` (both paths); `select(_:)`.
- Modify: `Sources/Search/Sleep.swift`: `awake(because:)`.
- Modify: `Sources/Search/App.swift`: `take(_:)` (after the ⌃1–9 branch), and the Tabs `CommandMenu`, after `Duplicate Tab`.
- Modify: `Sources/Search/TabBar.swift`: `TabMenu.body`.

**Interfaces:**
- Consumes: Task 1's rules, and Task 2's `splits`, `activeSplit` and `split(of:)`.
- Produces (used by Tasks 4–6):
  - `func Browser.newSplitPane()`
  - `func Browser.removeFromSplit(_ tab: Tab)`
  - `func Browser.canAddToSplit(_ tab: Tab) -> Bool`
  - `func Browser.addToSplit(_ tab: Tab)`
  - `func Browser.focusPane(_ tab: Tab)`
  - `func Browser.stepPane(_ direction: Int)`
  - `func Browser.resizeSplit(_ id: UUID, divider: Int, to fraction: Double)`
  - `func Browser.evenSplit(_ id: UUID)`

- [ ] **Step 1: The commands**

In `Browser.swift`, directly after `func split(of tab: Tab) -> Split?`, add:

```swift

    /// ⌃⇧=: a blank pane right of the tab you are on, its address field
    /// ready. A full split takes no more, and says so.
    func newSplitPane() {
        guard let beside = active else { return }
        let tab = Tab()
        guard let next = Splits.adding(tab.id, beside: beside.id, to: splits) else {
            NSSound.beep()
            return
        }
        prepare(tab)
        insert(tab, at: placeForNew())
        splits = next
        focusPane(tab)
        editing = true
        typed = ""
        rememberSession()
    }

    /// Out of its split, still open; the others widen, and a split left with
    /// one pane ends.
    func removeFromSplit(_ tab: Tab) {
        splits = Splits.removing(tab.id, from: splits)
        rememberSession()
    }

    /// Whether a tab can join the split on screen — or make one with the tab
    /// you are on.
    func canAddToSplit(_ tab: Tab) -> Bool {
        guard let active, tab.id != active.id, !tab.isBlank else { return false }
        guard let split = activeSplit else { return true }
        return !split.tabs.contains(tab.id) && split.tabs.count < Splits.most
    }

    /// A tab added as a pane right of the one you are on.
    func addToSplit(_ tab: Tab) {
        guard canAddToSplit(tab), let active, let next = Splits.adding(tab.id, beside: active.id, to: splits) else { return }
        splits = next
        focusPane(tab)
        rememberSession()
    }

    /// A pane made the one you are on, as a click in it does: without what
    /// selecting a tab also does — the peek, the reordering, the rest — since
    /// the split is already on screen.
    func focusPane(_ tab: Tab) {
        guard activeID != tab.id else { return }
        activeID = tab.id
        tab.touch()
        if !tab.wake() { tab.revive() }
    }

    /// ⌃⇧] and ⌃⇧[: the next or previous pane of the split on screen.
    func stepPane(_ direction: Int) {
        guard let split = activeSplit, let activeID, let at = split.tabs.firstIndex(of: activeID) else { return }
        let to = (at + direction + split.tabs.count) % split.tabs.count
        if let tab = tabs.first(where: { $0.id == split.tabs[to] }) { focusPane(tab) }
    }

    func resizeSplit(_ id: UUID, divider: Int, to fraction: Double) {
        splits = Splits.resizing(id, divider: divider, to: fraction, in: splits)
        rememberSession()
    }

    func evenSplit(_ id: UUID) {
        splits = Splits.evened(id, in: splits)
        rememberSession()
    }
```

`insert(_:at:)`, `prepare(_:)`, `placeForNew()`, `editing` and `typed` already exist in `Browser`. If `prepare` is private, `newSplitPane` is in the same file, so it can reach it. Mirror exactly how `select(_:)` wakes a tab (`wake()` returns `Bool`, and `revive()` otherwise).

- [ ] **Step 2: Showing a split wakes it**

In `select(_:)`, directly after the line that wakes the selected tab (`if !tab.wake() { tab.revive() }` or its equivalent), add:

```swift
        // A split is looked at whole: every pane of it wakes with the one
        // selected.
        if let split = split(of: tab) {
            for other in tabs where other.id != tab.id && split.tabs.contains(other.id) {
                if !other.wake() { other.revive() }
            }
        }
```

- [ ] **Step 3: ⌘W on a pane lands on its neighbour**

In `close(_:)`, at the start, before either landing path runs, add:

```swift
        // A pane closed or put down leaves its split, and you land on the pane
        // beside it — not on whichever tab you used last.
        let beside = activeID == tab.id ? Splits.neighbour(of: tab.id, in: splits) : nil
        if split(of: tab) != nil { splits = Splits.removing(tab.id, from: splits) }
```

If the function has early `guard`s, put this after them. Then, in **both** landing paths:
- the kept path, which after `tab.rest()` selects `back` or calls `newTab()`;
- the loose path, which after `tabs.remove(at: index)` selects `tabs[min(index, tabs.count - 1)]` when the closed tab was active.

Try the neighbour first, just before the path's own choice:

```swift
            if let beside, let pane = tabs.first(where: { $0.id == beside }) {
                select(pane)
            } else {
                … the path's existing choice, unchanged …
            }
```

Keep each path's session write exactly where it is, after the choice.

- [ ] **Step 4: The split on screen stays awake**

In `Sleep.swift`'s `awake(because:)`, directly after `if tab.id == activeID { return "on screen" }`, add:

```swift
        if let split = activeSplit, split.tabs.contains(tab.id) { return "on screen" }
```

Reach `activeSplit` the same way the function reaches `activeID`.

- [ ] **Step 5: The keys**

In `App.swift`'s `take(_:)`, directly after the ⌃1–9 branch (which ends with `browser.switchSpace(index: number - 1)`, `return true` and `}`), add:

```swift
        // Split view: ⌃⇧= a new pane, ⌃⇧- out of the split, ⌃⇧] and ⌃⇧[
        // between panes. By key code, so the keys are the same on any layout.
        if flags.contains([.control, .shift]), flags.isDisjoint(with: [.command, .option]) {
            switch event.keyCode {
            case 24: browser.newSplitPane(); return true
            case 27: if let tab = browser.active, browser.split(of: tab) != nil { browser.removeFromSplit(tab) }; return true
            case 30: browser.stepPane(1); return true
            case 33: browser.stepPane(-1); return true
            default: break
            }
        }
```

Use the same `flags` local the ⌃1–9 branch uses.

- [ ] **Step 6: The menus**

In the Tabs `CommandMenu` (`App.swift`), directly after the `Button("Duplicate Tab") { … }` block (its modifiers included), add:

```swift
                Divider()
                Button("New Split Pane") { browser.newSplitPane() }
                    .keyboardShortcut("=", modifiers: [.control, .shift])
                    .disabled(browser.active == nil)
                Button("Remove from Split") { if let tab = browser.active { browser.removeFromSplit(tab) } }
                    .keyboardShortcut("-", modifiers: [.control, .shift])
                    .disabled(browser.activeSplit == nil)
                Button("Next Pane") { browser.stepPane(1) }
                    .keyboardShortcut("]", modifiers: [.control, .shift])
                    .disabled(browser.activeSplit == nil)
                Button("Previous Pane") { browser.stepPane(-1) }
                    .keyboardShortcut("[", modifiers: [.control, .shift])
                    .disabled(browser.activeSplit == nil)
```

The key monitor answers first, so these shortcuts only label the menu.

In `TabMenu.body` (`TabBar.swift`), directly before the `Divider()` that precedes `Button("Close Tab", action: close)`, add:

```swift
        if browser.split(of: tab) != nil {
            Button("Remove from Split") { browser.removeFromSplit(tab) }
        } else if browser.canAddToSplit(tab) {
            Button("Add to Split") { browser.addToSplit(tab) }
        }
```

- [ ] **Step 7: Build and test**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -1`
Expected: `Build complete!`, then 109 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/Search/Browser.swift Sources/Search/Sleep.swift Sources/Search/App.swift Sources/Search/TabBar.swift
git commit -m "Split view's commands: ⌃⇧= for a pane, out of the split, between panes, and ⌘W that lands beside"
```

---

### Task 4: The split on screen

**Files:**
- Create: `Sources/Search/Split.swift`
- Modify: `Sources/Search/App.swift`: `ContentView.stage`.

**Interfaces:**
- Consumes:
  - `Browser.activeSplit`, `activeID`, `tabs`, `focusPane`, `resizeSplit`, `evenSplit`, `linkStatus`, `finding`, `suggesting`, `prefs.showsLinks`;
  - `Page(tab:)`, `LinkBubble`, `FindBar`, `AccountList`, `Palette`, `Motion`.
- Produces: `struct SplitStage: View`, with `static let gap: CGFloat = 6` and `static let corner: CGFloat`; `struct PageOverlays: ViewModifier`.

- [ ] **Step 1: `Split.swift`**

Create `Sources/Search/Split.swift`:

```swift
import AppKit
import SwiftUI

// Split view on screen: the split's tabs side by side, each a column as wide
// as its share, with a divider to drag between them. The pane you are on is
// the tab you are on; a click in another makes it so. See Splits.swift for
// the rules this only draws.

/// What sits over the page you are on — the link under the pointer, find,
/// the accounts for a sign-in field — on the one page, or on the focused
/// pane of a split, never across all of them.
struct PageOverlays: ViewModifier {
    @ObservedObject var browser: Browser
    let tab: Tab

    func body(content: Content) -> some View {
        content
            .overlay {
                if browser.prefs.showsLinks { LinkBubble(status: browser.linkStatus) }
            }
            .overlay(alignment: .topTrailing) {
                if browser.finding {
                    FindBar(browser: browser)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topLeading) {
                if let asked = browser.suggesting, asked.tab == tab.id {
                    AccountList(browser: browser, asked: asked)
                        .transition(.opacity)
                }
            }
            .animation(Motion.quick, value: browser.suggesting)
    }
}

/// The split on screen: its panes left to right, dividers between.
struct SplitStage: View {
    @ObservedObject var browser: Browser
    let split: Split

    /// The space between two panes, which is also where a divider is held.
    static let gap: CGFloat = 6
    /// The page's own rounding, for the ring on the pane you are on.
    static let corner: CGFloat = 0

    @State private var monitor: Any?

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - CGFloat(split.tabs.count - 1) * SplitStage.gap)
            HStack(spacing: 0) {
                ForEach(Array(split.tabs.enumerated()), id: \.element) { index, id in
                    if index > 0 {
                        SplitDivider(
                            drag: { x in
                                let before = Double(index - 1) * Double(SplitStage.gap) + Double(SplitStage.gap) / 2
                                browser.resizeSplit(split.id, divider: index - 1, to: (Double(x) - before) / Double(usable))
                            },
                            even: { browser.evenSplit(split.id) }
                        )
                    }
                    if let tab = browser.tabs.first(where: { $0.id == id }) {
                        pane(tab)
                            .frame(width: usable * CGFloat(split.widths.indices.contains(index) ? split.widths[index] : 1 / Double(split.tabs.count)))
                    }
                }
            }
            .coordinateSpace(name: "split")
        }
        .onAppear(perform: watchClicks)
        .onDisappear(perform: stopWatching)
    }

    @ViewBuilder
    private func pane(_ tab: Tab) -> some View {
        if tab.id == browser.activeID {
            Page(tab: tab)
                .modifier(PageOverlays(browser: browser, tab: tab))
                .overlay {
                    // The pane you are on, marked without dimming the others:
                    // they're there to be read.
                    RoundedRectangle(cornerRadius: SplitStage.corner, style: .continuous)
                        .strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
        } else {
            Page(tab: tab)
        }
    }

    /// A click in a pane makes it the one you are on. Looked at, never taken:
    /// the page still gets its click.
    private func watchClicks() {
        guard monitor == nil else { return }
        let browser = browser
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let panes = browser.activeSplit?.tabs ?? []
            for tab in browser.tabs where panes.contains(tab.id) {
                guard let web = tab.built, web.window === event.window else { continue }
                if web.bounds.contains(web.convert(event.locationInWindow, from: nil)) {
                    browser.focusPane(tab)
                    break
                }
            }
            return event
        }
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Between two panes: dragged, it moves the line between them; a
/// double-click evens every pane.
private struct SplitDivider: View {
    let drag: (CGFloat) -> Void
    let even: () -> Void

    @State private var hovering = false

    var body: some View {
        Color.clear
            .frame(width: SplitStage.gap)
            .overlay {
                Capsule()
                    .fill(Palette.ink.opacity(hovering ? 0.28 : 0.1))
                    .frame(width: 2, height: 36)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("split"))
                    .onChanged { drag($0.location.x) }
            )
            .onTapGesture(count: 2, perform: even)
            .animation(Motion.quick, value: hovering)
    }
}
```

Set `SplitStage.corner` to the corner radius `Page` rounds its page with. Find it in Stage.swift's `Page`: its `clipShape`, `RoundedRectangle`, or a `Metrics` constant. If `Page` isn't rounded, leave it at `0`.

- [ ] **Step 2: The stage draws the split**

In `App.swift`, replace the whole body of `ContentView.stage` (the `if let tab = browser.active { Page(tab: tab) .overlay … .animation(…) } else { Palette.ground }`) with:

```swift
        if let split = browser.activeSplit {
            SplitStage(browser: browser, split: split)
        } else if let tab = browser.active {
            Page(tab: tab)
                .modifier(PageOverlays(browser: browser, tab: tab))
        } else {
            Palette.ground
        }
```

Outside a split this is the same view as before, because `PageOverlays` holds those same three overlays and that same animation.

- [ ] **Step 3: Build and test**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -1`
Expected: `Build complete!`, then 109 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Search/Split.swift Sources/Search/App.swift
git commit -m "The split on screen: its panes side by side, dividers to drag, and a click that moves focus"
```

---

### Task 5: The split mark

**Files:**
- Modify: `Sources/Search/Split.swift` (append `SplitMark`).
- Modify: `Sources/Search/Side.swift`: `SideRow`'s leading marks and its `ground`; `PinSquare`.
- Modify: `Sources/Search/TabBar.swift`: `TabPill`'s marks (next to `tab.bench`/`tab.shy`), and its pinned square's overlays.

**Interfaces:**
- Consumes: `Browser.split(of:)` and `Browser.activeSplit` (Task 2).
- Produces: `struct SplitMark: View { var size: CGFloat = 9 }`.

- [ ] **Step 1: The mark**

Append to `Split.swift`:

```swift

/// On a tab in a split, wherever the tab is drawn: small, and quiet.
struct SplitMark: View {
    var size: CGFloat = 9

    var body: some View {
        Image(systemName: "rectangle.split.2x1")
            .font(.system(size: size))
            .foregroundStyle(Palette.muted)
            .accessibilityLabel("In a split")
    }
}
```

- [ ] **Step 2: Rows**

In `SideRow`, the leading `HStack` has `if tab.bench { … flask … }` and `if tab.shy { … eye.slash … }`. Directly before the `if tab.bench {` line, add:

```swift
                if browser.split(of: tab) != nil { SplitMark() }
```

Add to `SideRow`:

```swift
    /// In the split on screen, though not the pane you are on.
    private var onScreen: Bool { !live && browser.activeSplit?.tabs.contains(tab.id) == true }
```

In `SideRow`'s `ground`, the chain is `if live { … } else if hovering { … }`. Make it `if live { … } else if onScreen { … } else if hovering { … }`, with:

```swift
        } else if onScreen {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.wash.opacity(0.5))
```

- [ ] **Step 3: Favorite cards and the top bar**

In `PinSquare`, next to its `.overlay(alignment: .bottom) { … AwayDot … }`, add:

```swift
        .overlay(alignment: .topTrailing) {
            if browser.split(of: tab) != nil { SplitMark(size: max(6, scale * 7 / 34)).padding(scale * 3 / 34) }
        }
```

In `TabPill`:
- next to its `tab.bench`/`tab.shy` marks in the titled pill, add `if browser.split(of: tab) != nil { SplitMark() }`;
- on the pinned square, next to its AwayDot overlay, add `.overlay(alignment: .topTrailing) { if browser.split(of: tab) != nil { SplitMark(size: 6).padding(2) } }`.

`TabPill` already has `browser` in scope.

- [ ] **Step 4: Build and test**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -1`
Expected: `Build complete!`, then 109 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Search/Split.swift Sources/Search/Side.swift Sources/Search/TabBar.swift
git commit -m "A tab in a split wears a small mark wherever it is drawn, and the split on screen shows in the column"
```

---

### Task 6: Bench, end-to-end check, changelog

**Files:**
- Modify: `Sources/Search/Bench.swift`: a `case "split":` before `case "text":`, and `"split",` in the `"commands": [` list (about line 1384).
- Modify: `bench`: the request building, the output and the docstring.
- Modify: `CHANGELOG.md`

**Interfaces:**
- Produces: `./bench --test split new | add ID | remove ID | focus ID | resize DIVIDER FRACTION | even | list`. Every answer includes the panes on screen.

- [ ] **Step 1: The bench verb**

In `Bench.swift`, directly before `case "text":`, add:

```swift
        case "split":
            // Split view driven as its keys and menus would. Changing the
            // panes changes your window: only on a SEARCH_PROBE run.
            guard Store.testing else { answer(["error": "split only works on a --test run — it changes your window"]); return }
            switch request["what"] as? String ?? "list" {
            case "new": browser.newSplitPane()
            case "add":
                guard let tab = find(request, in: browser) else { answer(missing(request)); return }
                browser.addToSplit(tab)
            case "remove":
                guard let tab = find(request, in: browser) else { answer(missing(request)); return }
                browser.removeFromSplit(tab)
            case "focus":
                guard let tab = find(request, in: browser) else { answer(missing(request)); return }
                browser.select(tab)
            case "resize":
                guard let split = browser.activeSplit else { answer(["error": "no split on screen"]); return }
                browser.resizeSplit(split.id, divider: request["divider"] as? Int ?? 0, to: request["fraction"] as? Double ?? 0.5)
            case "even":
                guard let split = browser.activeSplit else { answer(["error": "no split on screen"]); return }
                browser.evenSplit(split.id)
            case "list": break
            default: answer(["error": "split needs new, add, remove, focus, resize, even or list"]); return
            }
            // Where each pane sits in the window, read from its page's own
            // view: the layout as drawn, not as meant.
            let split = browser.activeSplit
            answer([
                "splits": browser.splits.count,
                "active": browser.active.map(Bench.short) ?? "",
                "panes": (split?.tabs ?? []).enumerated().map { index, id -> [String: Any] in
                    let tab = browser.tabs.first { $0.id == id }
                    let frame = tab?.built.map { $0.convert($0.bounds, to: nil) } ?? .zero
                    return [
                        "id": tab.map(Bench.short) ?? "?",
                        "width": split.map { $0.widths.indices.contains(index) ? $0.widths[index] : 0 } ?? 0,
                        "x": Double(frame.minX), "w": Double(frame.width),
                        "focused": id == browser.activeID,
                    ]
                },
            ])

```

Add `"split",` to the `"commands": [` list.

- [ ] **Step 2: The client**

In `bench`, directly after the `elif verb == "folder":` request branch, add:

```python
    elif verb == "split":
        what, a = (args[0], args[1:]) if args else ("list", [])
        need = {"new": 0, "add": 1, "remove": 1, "focus": 1, "resize": 2, "even": 0, "list": 0}
        if what not in need or len(a) != need[what]:
            sys.exit("usage: bench split new|add ID|remove ID|focus ID|resize DIVIDER FRACTION|even|list")
        request["what"] = what
        if what in ("add", "remove", "focus"): request["id"] = a[0]
        elif what == "resize": request["divider"], request["fraction"] = int(a[0]), float(a[1])
```

In the output section, directly before `elif verb == "tabs":`, add:

```python
    elif verb == "split":
        print(f"splits {answer.get('splits')}  active {answer.get('active')}")
        for p in answer.get("panes", []):
            print(f"{'▶' if p.get('focused') else ' '} {p['id']}  share {p['width']:.2f}  x {p['x']:.0f}  w {p['w']:.0f}")
```

In the docstring, after the `./bench folder …` lines, add:

```
    ./bench split new|add ID|remove ID|focus ID|resize DIVIDER FRACTION|even|list
                                       split view, and each pane's share and place in the window — --test runs only
```

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -1`
Expected: `Build complete!`, then 109 tests pass.

- [ ] **Step 3: Start the test run**

```bash
mkdir -p /tmp/split-site && cd /tmp/split-site && for p in a b c d e; do printf '<title>%s</title><input id=f><a id=l href="/%s.html">link</a>' $p $p > $p.html; done && cd - >/dev/null
nohup python3 -m http.server 8767 --bind 127.0.0.1 --directory /tmp/split-site >/dev/null 2>&1 & echo $! > /tmp/split-server.pid
D="$HOME/Library/Application Support/Search (test)"
cp "$D/session.json" /tmp/session.split-backup.json 2>/dev/null || true
nohup .build/debug/Search >/tmp/search-split.log 2>&1 &
sleep 4 && ./bench --test tabs | tail -3
```

If the Welcome screen covers the window, run `./bench --test ui welcome off` (it's the test world only).

- [ ] **Step 4: ⌃⇧= through the real key path, focus by click**

```bash
A=$(./bench --test open http://127.0.0.1:8767/a.html) && ./bench --test wait $A >/dev/null && ./bench --test select $A >/dev/null
./bench --test press 24 = ctrl shift && sleep 1 && ./bench --test split list
```

Expected: `splits 1`, and two panes, the first being A's id and the second a new tab, which is focused (▶). Their shares are 0.50 each, and their `x`/`w` put them side by side (the second's `x` is about the first's `x + w + 6`). If `press`'s argument order differs, check `./bench help` (`press CODE CHARS [MODS…]`).

```bash
./bench --test press 24 = ctrl shift && ./bench --test press 24 = ctrl shift && ./bench --test split list
./bench --test press 24 = ctrl shift && ./bench --test split list
```

Expected: four panes after the first line, all at shares of 0.25. The last press is refused: still four.

Now a real click in A's pane:

```bash
./bench --test tap $A '#f' && sleep 0.5 && ./bench --test split list
./bench --test eval $A "document.activeElement && document.activeElement.id"
```

Expected: A is focused (▶), and the page still got its click: `f`.

- [ ] **Step 5: ⌘W on a pane, leaving the split and coming back**

Focus the second pane with `./bench --test split focus <its id from the list>`, then press ⌘W through the real path: `./bench --test press 13 w cmd`. Run `./bench --test split list`.
Expected: three panes, with focus on A, the pane that was to the left of the closed one.

```bash
B=$(./bench --test open http://127.0.0.1:8767/b.html) && ./bench --test wait $B >/dev/null && ./bench --test split focus $B && ./bench --test split list
./bench --test split focus $A && ./bench --test split list
```

Expected:
- focusing B (not in the split): `splits 1`, with no panes listed, because the split isn't on screen;
- focusing A: its three panes return, with A focused.

```bash
./bench --test split resize 0 0.3 && ./bench --test split list
./bench --test split even && ./bench --test split list
```

Expected: after `resize`, the first share is 0.30, the second has taken up the rest of the pair, and the third is unchanged. After `even`, every share is 0.33.

- [ ] **Step 6: A tab closed another way leaves its split**

Focus a pane other than A (`./bench --test split focus <id>`), then close A by id: `./bench --test close $A`. A is a bench tab, so the bench may close it. Run `./bench --test split list`.
Expected: A is gone from the panes, no pane shows a closed tab, and the other two remain as a split.

- [ ] **Step 7: A relaunch, and a broken entry**

```bash
pkill -f "\.build/debug/Search"; sleep 1
cat > "$D/session.json" <<'EOF'
{"tabs":[
  {"url":"http://127.0.0.1:8767/a.html","title":"a"},
  {"url":"http://127.0.0.1:8767/b.html","title":"b"},
  {"url":"http://127.0.0.1:8767/c.html","title":"c"}
],"active":0,
 "splits":[{"tabs":[0,2],"widths":[0.35,0.65]},{"tabs":"broken"}]}
EOF
nohup .build/debug/Search >/tmp/search-split.log 2>&1 &
sleep 4 && ./bench --test split list && ./bench --test tabs | tail -3
```

Expected:
- `splits 1`, with two panes (a and c) at shares of 0.35 and 0.65, and a focused;
- all three tabs are listed.

Then force a write and read it back:
1. Run `./bench --test split focus <c's id>`, then `./bench --test split focus <a's id>`.
2. Run `sleep 2`, for the debounced save.
3. Run `python3 -m json.tool "$D/session.json" | grep -A6 '"splits"'`.

Expected: `"tabs": [0, 2]`, with widths 0.35 and 0.65.

- [ ] **Step 8: The marks**

With the split on screen, run `./bench --test column /tmp/split-column.png`. If the tabs are across the top, run `./bench --test ui sidebar on` first, and turn it off in Step 9.
Expected: a and c show the ◫ mark. c, which is on screen but not focused, has the lighter ground; a has the normal highlight. Record the path.

- [ ] **Step 9: Clean up**

```bash
./bench --test ui sidebar off   # only if Step 8 turned it on
pkill -f "\.build/debug/Search"; kill "$(cat /tmp/split-server.pid)"
[ -f /tmp/session.split-backup.json ] && cp /tmp/session.split-backup.json "$D/session.json"
pgrep -fl "\.build/debug/Search|http.server 8767" || echo "clean"
```

Expected: `clean`.

- [ ] **Step 10: Changelog**

In `CHANGELOG.md`, under `## Unreleased` › `### Added`, add this as the first line of the list:

```markdown
- Split view, as in Arc: ⌃⇧= puts a new pane beside the tab you're on, up to four side by side, with dividers to drag (a double-click evens them). Click a pane to work in it; ⌃⇧] and ⌃⇧[ move between panes, ⌃⇧- takes one out, and Add to Split in a tab's menu brings any tab in, a favorite or a pin included. A split stays together: leave it for another tab and it's there when you come back, marked ◫ in the column, and it's saved with the session.
```

- [ ] **Step 11: Commit**

```bash
git add Sources/Search/Bench.swift bench CHANGELOG.md
git commit -m "The bench can drive split view and read where each pane sits, and the changelog says what split view is"
```

The controller pushes `split-view` and opens its PR after the final review:
`gh pr create --repo Richard-DEPIERRE/Search --base peek-links --head split-view`.
