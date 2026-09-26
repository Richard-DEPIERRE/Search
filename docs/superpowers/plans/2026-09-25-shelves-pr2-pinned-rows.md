# Shelves PR 2 — pinned rows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Arc's second shelf. Pins are full-width rows under the favorite cards and above a divider, with a ↩︎ button when they're away from their page. Each tab gets menu actions to pin it, and to move it between favorites and pins.

**Architecture:** The data model from PR 1 already has `Shelf.pins`. This PR adds one browser entry point, `Browser.keep(_:on:)`, used for favoriting, pinning and moving between the two. The sidebar gets a pinned-rows block, drawn with the existing `SideRow` in a "kept" mode and reordered with the existing `Carried` drag. A trip home now ends at the page's first commit (`didCommit`), not when loading stops, so an in-flight load can no longer cut it short.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftPM, AppKit + SwiftUI + WebKit, Swift Testing, and `./bench`.

**Spec:** `docs/superpowers/specs/2026-09-25-sidebar-favorites-pins-folders-design.md`. This plan is **PR 2** of §5, stacked on PR 1 (branch `sidebar-shelves`, Richard-DEPIERRE/Search#1). It works on branch `sidebar-pins`, cut from `sidebar-shelves`, and its PR's base is `sidebar-shelves`.

## Global Constraints

- macOS 14 or later. No dependencies beyond what Apple ships. Swift language mode v5 for every target.
- `pin != nil` keeps its meaning: the tab is *kept* (a favorite or a pin). `Browser.pinnedCount` keeps its meaning too: the count of all kept tabs.
- Order invariant: `[favorites…] [pins…] [today's tabs…]`, kept by `Browser.tidyTabs()`.
- Pinned rows are 28pt (`SideBar.row`), with `SideBar.gap` (2pt) between rows, the same as today's tab rows.
- The divider is drawn only when there are pins.
- "Pin" puts a tab at the end of the pins, outside any folder. "Add to Favorites" puts it at the end of the favorites.
- Drag-and-drop between sections is not in this PR. `Browser.move` still refuses to cross sections.
- The horizontal tab bar needs no layout change. Kept tabs are squares already.
- `Shelves.swift` imports Foundation only.
- Extensions that pin a tab (`Extensions.swift`) keep getting a **favorite**, which is today's behaviour.
- Comments follow the repo's voice: plain sentences explaining *why*. No attribution lines in commits or PR bodies. Never run `./ideas`.
- CHANGELOG.md: one line under `## Unreleased` › `### Added`.
- Tests and end-to-end checks drive only the test instance (`.build/debug/Search`, `./bench --test`). Never touch `~/Library/Application Support/Search/`.

## Review Focus

1. **`rowsEnd` and the pinned block's height disagree.** Then the window drags from a pin row, or a row stops answering clicks. Pinned by the `./bench --test hit` checks in Task 4, Step 6.
2. **Dragging or placing a pin outside the pins.** Moving a pin to index 0, among the favorites, must be refused. Pinned by the `canMove` tests from PR 1 and the `./bench --test place` check in Task 4, Step 3.
3. **Relaunching with pins saved.** The pins come back as rows in the same order, still pins, with their homes. Pinned by the seeded-session check in Task 4, Step 7.
4. **Back to Pinned Page while a slow page is still loading.** The trip must still count its redirect as home. Pinned by the `/slow` check in Task 4, Step 5, and by commit-based trips in Task 2.
5. **Moving between shelves.** A favorite moved to the pins becomes the first pin, a pin moved to favorites becomes the last favorite, and neither loses its home. Pinned by the `ShelfMoveTests` in Task 1 and the bench check in Task 4, Step 3.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/Search/Shelves.swift` | Modify | Add `Shelves.count(_:of:)`; tighten the `canBeHome` comment. |
| `Tests/SearchTests/ShelvesTests.swift` | Modify | `CountTests` and `ShelfMoveTests`. |
| `Sources/Search/Browser.swift` | Modify | `keep(_:on:)` replaces `pin(_:)`; add `favoriteCount` and `pinCount`; `didCommit` ends a trip home. |
| `Sources/Search/Extensions.swift` | Modify | Two `browser.pin(tab)` calls become `browser.keep(tab, on: .favorites)`. |
| `Sources/Search/TabBar.swift` | Modify | `KeptTabCommands`: Pin, Move to Pins or Favorites, Unpin; Set Pinned Page disabled where no home can be. |
| `Sources/Search/Tab.swift` | Modify | A trip home ends at commit (`committed()`, `tripFailed()`), no longer at `isLoading` false or at every URL change. |
| `Sources/Search/Side.swift` | Modify | The favorites grid shows favorites only; pin rows, divider, `rowsEnd` and the space preview; `SideRow` gets a kept mode with ↩︎. |
| `Sources/Search/Bench.swift` | Modify | `keep ID pins`; add `keep` and `home` to the command list. |
| `bench` | Modify | The client accepts `pins`; usage text. |
| `CHANGELOG.md` | Modify | One "Added" line. |

---

### Task 1: One way to keep a tab, and menus for both shelves

**Files:**
- Modify: `Sources/Search/Shelves.swift`, the `canBeHome` doc comment, plus a new function at the end of `enum Shelves`.
- Modify: `Tests/SearchTests/ShelvesTests.swift`
- Modify: `Sources/Search/Browser.swift`: `func pin(_ tab: Tab)`, and the `pinnedCount` line.
- Modify: `Sources/Search/Extensions.swift`, two call sites (search for `browser.pin(tab)`).
- Modify: `Sources/Search/TabBar.swift`, `KeptTabCommands.body`.
- Modify, if Step 8 finds a caller there: `Sources/Search/Bench.swift`.

**Interfaces:**
- Consumes (from PR 1):
  - `Slot`, `Shelves.section(of:)`, `Shelves.Section`, `Shelves.canBeHome(_:)`
  - `Tab.pin`, `shelf`, `folder`, `away`, `address`, `home`, `remember(home:)`
  - `Browser.slots` (private), `tidyTabs()`, `unpin(_:)`, `goHome(_:)`, `setHome(_:)`, `editLetter(_:)`, `editingPin`
- Produces (used by Tasks 3–4):
  - `static func Shelves.count(_ slots: [Slot], of wanted: Shelves.Section) -> Int`
  - `var Browser.favoriteCount: Int` and `var Browser.pinCount: Int`
  - `func Browser.keep(_ tab: Tab, on shelf: Shelf)`, which makes a tab kept on `shelf`, or moves a kept tab there. It always writes the session at once.
  - `Browser.pin(_:)` no longer exists.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SearchTests/ShelvesTests.swift`. The helpers `slot(_:kept:_:folder:)` and `work` are already at the top of that file.

```swift
@Suite struct CountTests {
    let row = [slot(1, kept: true), slot(2, kept: true, .pins), slot(3, kept: true, .pins), slot(4)]

    @Test func eachShelfCountsItsOwn() {
        #expect(Shelves.count(row, of: .favorites) == 1)
        #expect(Shelves.count(row, of: .pins) == 2)
        #expect(Shelves.count(row, of: .loose) == 1)
    }

    @Test func anEmptyRowHasNone() {
        #expect(Shelves.count([], of: .pins) == 0)
    }
}

@Suite struct ShelfMoveTests {
    // What Browser.keep(_:on:) relies on: it changes a tab's shelf and
    // tidies, and tidying is stable — so where a moved tab lands follows from
    // where it stood.

    @Test func aFavoriteMovedToPinsBecomesTheFirstPin() {
        var row = [slot(1, kept: true), slot(2, kept: true), slot(3, kept: true, .pins), slot(4)]
        row[1].shelf = .pins
        let (out, _) = Shelves.tidy(row, folders: [])
        #expect(out.map(\.id) == [row[0].id, row[1].id, row[2].id, row[3].id])
        #expect(Shelves.section(of: out[1]) == .pins)
    }

    @Test func aPinMovedToFavoritesBecomesTheLastFavorite() {
        var row = [slot(1, kept: true), slot(2, kept: true, .pins), slot(3, kept: true, .pins), slot(4)]
        row[2].shelf = .favorites
        let (out, _) = Shelves.tidy(row, folders: [])
        #expect(out.map(\.id) == [row[0].id, row[2].id, row[1].id, row[3].id])
    }

    @Test func aTabPinnedGoesToTheEndOfThePins() {
        var row = [slot(1, kept: true), slot(2, kept: true, .pins), slot(3), slot(4)]
        row[3].kept = true
        row[3].shelf = .pins
        let (out, _) = Shelves.tidy(row, folders: [])
        #expect(out.map(\.id) == [row[0].id, row[1].id, row[3].id, row[2].id])
    }

    @Test func aPinMovedToFavoritesLeavesItsFolder() {
        var row = [slot(1, kept: true, .pins, folder: work.id), slot(2, kept: true, .pins, folder: work.id)]
        row[0].shelf = .favorites
        let (out, folders) = Shelves.tidy(row, folders: [work])
        #expect(out[0].folder == nil)
        #expect(folders == [work])
    }
}
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `swift test 2>&1 | tail -20`
Expected: a compile failure, `type 'Shelves' has no member 'count'`. The `ShelfMoveTests` would pass on their own, since they pin down existing `tidy` behaviour. They exist to fix the contract `keep(_:on:)` relies on.

- [ ] **Step 3: Add `Shelves.count` and tighten the `canBeHome` comment**

In `Sources/Search/Shelves.swift`, replace:

```swift
    /// Whether a page is somewhere a kept tab can go back to. about:blank,
    /// or an extension's own page, is not: ⌘W would put the tab down there,
    /// the session saves only real pages, and the tab would be gone.
```

with:

```swift
    /// Whether a page is somewhere a kept tab can go back to. about:blank,
    /// or an extension's own page, is not: ⌘W would put the tab down there
    /// and the session, which saves only web pages, would lose it. A file
    /// on this Mac can be a home for as long as the app is open; like any
    /// file tab, it isn't brought back at the next launch.
```

Then, directly before the closing brace of `enum Shelves`, after `savedAddress`, add:

```swift

    /// How many tabs of the row are in one section.
    static func count(_ slots: [Slot], of wanted: Section) -> Int {
        slots.filter { section(of: $0) == wanted }.count
    }
```

- [ ] **Step 4: Run the tests and check they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `✔ Test run with 32 tests in 8 suites passed`. PR 1 left 26 tests in 6 suites; this adds 2 in `CountTests` and 4 in `ShelfMoveTests`.

- [ ] **Step 5: `keep(_:on:)` replaces `pin(_:)`, and add the counts**

In `Sources/Search/Browser.swift`, directly after the line `var pinnedCount: Int { tabs.filter { $0.pin != nil }.count }`, add:

```swift
    /// The cards at the top of the column, and the rows under them.
    var favoriteCount: Int { Shelves.count(slots, of: .favorites) }
    var pinCount: Int { Shelves.count(slots, of: .pins) }
```

Replace the whole `func pin(_ tab: Tab) { … }`. It begins `func pin(_ tab: Tab) {` and ends just before `/// Change Letter, or a double-click on the square itself.`. Replace it with:

```swift
    /// A tab made a favorite or a pin, or a kept one moved from one shelf to
    /// the other. Everything that keeps a tab comes through here: the menus,
    /// an extension pinning one (a favorite, as a pinned tab has always been),
    /// the bench.
    func keep(_ tab: Tab, on shelf: Shelf) {
        if tab.pin == nil {
            tab.pin = tab.monogram
            tab.shelf = shelf
            // The page it is on is the page it goes back to — when it is on a
            // page. An extension can pin a tab still at about:blank; that
            // one takes its first real page as home instead (Tab's `\.url`).
            tab.remember(home: Shelves.canBeHome(tab.address) ? tab.address : nil)
        } else if tab.shelf != shelf {
            if editingPin == tab.id { editingPin = nil }
            tab.shelf = shelf
            // Folders hold pins only.
            tab.folder = nil
        }
        // Tidying leaves every other tab where it is: one newly kept goes to
        // the end of its shelf, a favorite moved down becomes the first pin,
        // a pin moved up the last favorite — the places nearest where each
        // already stood.
        tidyTabs()
        // No dialog and no waiting cursor: the letter is taken from the
        // address and applied. Changing it is a separate act, for the day it
        // matters — which is why it is not folded into this one.
        writeSession(now: true)
    }
```

- [ ] **Step 6: Extensions keep getting favorites**

In `Sources/Search/Extensions.swift`, change both occurrences of `browser.pin(tab)` to `browser.keep(tab, on: .favorites)`. There is one near line 905 (`if configuration.shouldBePinned { … }`) and one near line 1034 (`if pinned, tab.pin == nil { … }`). Leave the `browser.unpin(tab)` next to the second one as it is.

- [ ] **Step 7: The menus for both shelves**

In `Sources/Search/TabBar.swift`, replace the body of `KeptTabCommands`:

```swift
    var body: some View {
        if tab.pin == nil {
            Button("Add to Favorites") { browser.pin(tab) }
                .disabled(tab.isBlank)
        } else {
            Button("Change Letter") { browser.editLetter(tab) }
            Button("Remove from Favorites") { browser.unpin(tab) }
            Button("Back to Pinned Page") { browser.goHome(tab) }
                .disabled(!tab.away)
            // Offered away from home, and also to a kept tab with no home
            // at all — one an extension pinned blank — which could never
            // get one otherwise.
            Button("Set Pinned Page to This Page") { browser.setHome(tab) }
                .disabled(tab.address == nil || (tab.home != nil && !tab.away))
        }
    }
```

with:

```swift
    var body: some View {
        if tab.pin == nil {
            Button("Add to Favorites") { browser.keep(tab, on: .favorites) }
                .disabled(tab.isBlank)
            Button("Pin") { browser.keep(tab, on: .pins) }
                .disabled(tab.isBlank)
        } else if tab.shelf == .favorites {
            Button("Change Letter") { browser.editLetter(tab) }
            Button("Move to Pins") { browser.keep(tab, on: .pins) }
            Button("Remove from Favorites") { browser.unpin(tab) }
        } else {
            Button("Move to Favorites") { browser.keep(tab, on: .favorites) }
            Button("Unpin") { browser.unpin(tab) }
        }
        if tab.pin != nil {
            Button("Back to Pinned Page") { browser.goHome(tab) }
                .disabled(!tab.away)
            // Offered away from home, and also to a kept tab with no home
            // at all — one an extension pinned blank — which could never get
            // one otherwise. Never on a page that can't be a home (about:blank,
            // an extension's page): setHome would ignore it.
            Button("Set Pinned Page to This Page") { browser.setHome(tab) }
                .disabled(!Shelves.canBeHome(tab.address) || (tab.home != nil && !tab.away))
        }
    }
```

`Shelves.canBeHome(nil)` is false, which covers the old `tab.address == nil` check.

- [ ] **Step 8: Check nothing else calls `pin(_:)`**

Run: `grep -rn "browser\.pin(\|self\.pin(\| pin(tab" Sources/Search`
Expected: no output. If a call remains, for example `browser.pin(tab)` in `Bench.swift`'s `case "keep":`, change it to `browser.keep(tab, on: .favorites)`.

- [ ] **Step 9: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then `✔ Test run with 32 tests in 8 suites passed`.

- [ ] **Step 10: Commit**

```bash
git add Sources/Search/Shelves.swift Tests/SearchTests/ShelvesTests.swift Sources/Search/Browser.swift Sources/Search/Extensions.swift Sources/Search/TabBar.swift Sources/Search/Bench.swift
git commit -m "One way to keep a tab, as a favorite or a pin, and menus that move it between the two"
```

(`Bench.swift` is in the list only in case Step 8 changed it. `git add` of an unchanged file does nothing.)

---

### Task 2: A trip home ends when the page commits

**Files:**
- Modify: `Sources/Search/Tab.swift`: the `\.url` observer, the `\.isLoading` observer, and new methods after `goHome()`.
- Modify: `Sources/Search/Browser.swift`: `webView(_:didCommit:)` and `webView(_:didFailProvisionalNavigation:withError:)`.

**Interfaces:**
- Consumes: `Tab.homing` (private), `Tab.landed` (`private(set)`), `Tab.built`, `Browser.tab(for:)`.
- Produces:
  - `func Tab.committed()`. It ends a trip home at its first main-frame commit, and records `landed` as the committed address.
  - `func Tab.tripFailed()`. It ends a trip home that never arrived.

**Why:** today a trip home ends when `isLoading` turns false. When Back to Pinned Page is pressed while another page is still loading, WebKit reports `isLoading` false as it cancels that load. The trip then ends before the home page's redirects arrive, and a redirecting home reads as away. The spec (§1) defines `landed` as "the first address committed after a go back to home". Server redirects are all followed before the commit, so the commit is exactly the moment the trip arrives.

- [ ] **Step 1: Stop recording every URL change as the landing**

In `Tab.swift`, in the `\.url` observer, delete this one line:

```swift
                    if self.homing { self.landed = fresh }
```

Keep the lines around it, including the "Kept before it had a page to keep" block.

- [ ] **Step 2: Stop ending the trip on `isLoading`**

In the `\.isLoading` observer, replace:

```swift
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.loading = self.built?.isLoading ?? false
                    // Arrived: anything after this is you going somewhere.
                    if !self.loading { self.homing = false }
                }
```

with:

```swift
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.loading = self.built?.isLoading ?? false
                }
```

- [ ] **Step 3: End the trip at commit, or when it fails**

In `Tab.swift`, directly after the closing brace of `func goHome()`, add:

```swift

    /// The page has committed. A trip home ends here, and where it arrived,
    /// the server's redirects already followed, counts as home too. Not
    /// when loading stops: a load still running when the trip began stops
    /// first, and the trip would end before home had answered.
    func committed() {
        guard homing else { return }
        homing = false
        landed = built?.url
    }

    /// The trip home never arrived: no host, no network. Whatever is
    /// committed next is you going somewhere, not home.
    func tripFailed() {
        homing = false
    }
```

- [ ] **Step 4: Tell the tab**

In `Browser.swift`, in `func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!)`, directly after `guard let tab = tab(for: webView) else { return }`, add:

```swift
        tab.committed()
```

In `webView(_:didFailProvisionalNavigation:withError:)`, replace its body:

```swift
        fail(webView, error)
```

with:

```swift
        tab(for: webView)?.tripFailed()
        fail(webView, error)
```

- [ ] **Step 5: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then 32 tests pass. The behaviour is checked end to end in Task 4, Steps 4–5.

- [ ] **Step 6: Commit**

```bash
git add Sources/Search/Tab.swift Sources/Search/Browser.swift
git commit -m "A trip home ends when the page commits, so a load still running can't cut it short"
```

---

### Task 3: Pins as rows in the column

**Files:**
- Modify: `Sources/Search/Side.swift`:
  - the `SideBar` constants (near line 31);
  - the current-space branch of `page(_:pill:)` (near line 176);
  - `preview(_:pill:)`, `rowsEnd`, the grid helpers (`pinnedTabs`, `pinWidth`, `pinTarget`, `pinned`), `loose` and `rows`;
  - `SideRow`.

**Interfaces:**
- Consumes:
  - `Browser.favoriteCount`, `pinCount`, `pinnedCount`, `move(_:to:)`, `close(_:)`, `select(_:)`, `goHome(_:)`, `beginTabRename(_:)`, `beginTabEdit(_:)` (Task 1 and earlier)
  - `Tab.shelf`, `away`, `pin`
  - `Carried` (TabBar.swift), `Palette.hairline`, `Palette.muted`, `Palette.ink`
- Produces: nothing new for other tasks. It's the view.

- [ ] **Step 1: Constants**

In `struct SideBar`, after `private static let pinGap: CGFloat = 4`, add:

```swift
    /// The line between the pins and the day's tabs, with its air.
    private static let divider: CGFloat = 13
```

- [ ] **Step 2: The grid is the favorites**

In `Side.swift`, replace:

```swift
    private var pinnedTabs: [Tab] { browser.tabs.filter { $0.pin != nil } }
```

with:

```swift
    private var favoriteTabs: [Tab] { browser.tabs.filter { $0.pin != nil && $0.shelf == .favorites } }
    private var pinTabs: [Tab] { browser.tabs.filter { $0.pin != nil && $0.shelf == .pins } }
```

Then, in the grid code only, change these (search each one):
- `let tabs = pinnedTabs` in `private var pinned: some View` → `let tabs = favoriteTabs`
- `max(0, pinnedTabs.count - 1)` in `pinTarget` → `max(0, favoriteTabs.count - 1)`
- `private var pinWidth: CGFloat { pinWidth(for: browser.pinnedCount) }` → `private var pinWidth: CGFloat { pinWidth(for: browser.favoriteCount) }`
- in `page(_:pill:)`'s current-space branch, `if browser.pinnedCount > 0 {` (just before `pinned`) → `if browser.favoriteCount > 0 {`

Then run `grep -n "pinnedTabs" Sources/Search/Side.swift`. Expected: no output.

The grid's live reorder calls `browser.move(tab, to: target)` with an index among the favorites. Favorites come first in `tabs`, so that index is already the right one. Leave it.

- [ ] **Step 3: The pin rows and the divider**

Directly after the closing brace of `private var loose: some View`, add:

```swift

    /// The pins: rows under the cards, for the pages kept all day that want
    /// their titles rather than a letter. Carried within the pins only;
    /// `move` keeps them there.
    private var pinRows: some View {
        VStack(spacing: SideBar.gap) {
            ForEach(Array(pinTabs.enumerated()), id: \.element.id) { index, tab in
                SideRow(
                    browser: browser,
                    prefs: prefs,
                    tab: tab,
                    live: tab.id == browser.activeID,
                    pill: pill,
                    close: { browser.close(tab) }
                )
                // Positions here are among the pins; the favorites sit in
                // front of them in the real list.
                .modifier(Carried(index: index, count: pinTabs.count, step: SideBar.row + SideBar.gap, vertical: true, space: "pins") {
                    browser.move(tab, to: $0 + browser.favoriteCount)
                })
            }
        }
        .coordinateSpace(name: "pins")
    }

    /// Between the pins and the day's tabs, and only when there are pins.
    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.horizontal, 10)
            .frame(height: SideBar.divider)
    }

    /// The pins and their divider, as tall as they are drawn: `rowsEnd`
    /// adds this same number, so the window's drag area starts exactly
    /// where the rows stop.
    private var pinBlock: CGFloat {
        let pins = CGFloat(browser.pinCount)
        return pins == 0 ? 0 : pins * (SideBar.row + SideBar.gap) - SideBar.gap + SideBar.divider
    }
```

Replace `private var rows: some View`:

```swift
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            loose
            newTab
        }
    }
```

with:

```swift
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if browser.pinCount > 0 {
                pinRows
                divider
            }
            loose
            newTab
        }
    }
```

- [ ] **Step 4: Where the rows stop**

Replace `private var rowsEnd: CGFloat { … }`:

```swift
    private var rowsEnd: CGFloat {
        let pins = browser.pinnedCount
        let cols = SideBar.pinColumns(pins)
        let pinRows = pins == 0 ? 0 : (pins + cols - 1) / cols
        let pinBlock = pinRows == 0 ? 0
            : CGFloat(pinRows) * pinHeight + CGFloat(pinRows - 1) * SideBar.pinGap + 10
        let loose = CGFloat(browser.tabs.count - pins) * (SideBar.row + SideBar.gap)
        return Metrics.strip + pinBlock + loose + SideBar.row + 8
    }
```

with:

```swift
    private var rowsEnd: CGFloat {
        let favorites = browser.favoriteCount
        let cols = SideBar.pinColumns(favorites)
        let gridRows = favorites == 0 ? 0 : (favorites + cols - 1) / cols
        let grid = gridRows == 0 ? 0
            : CGFloat(gridRows) * pinHeight + CGFloat(gridRows - 1) * SideBar.pinGap + 10
        let loose = CGFloat(browser.tabs.count - browser.pinnedCount) * (SideBar.row + SideBar.gap)
        return Metrics.strip + grid + pinBlock + loose + SideBar.row + 8
    }
```

The `loose` offset in `private var loose` stays `$0 + browser.pinnedCount`. Today's tabs come after every kept tab.

- [ ] **Step 5: Another space's column, as it will look**

Replace the start of `preview(_:pill:)`:

```swift
    private func preview(_ row: Parked, pill: Namespace.ID) -> some View {
        let pins = row.tabs.filter { $0.pin != nil }
        let rest = row.tabs.filter { $0.pin == nil }
```

with:

```swift
    private func preview(_ row: Parked, pill: Namespace.ID) -> some View {
        let pins = row.tabs.filter { $0.pin != nil && $0.shelf == .favorites }
        let pinsAsRows = row.tabs.filter { $0.pin != nil && $0.shelf == .pins }
        let rest = row.tabs.filter { $0.pin == nil }
```

Here `pins` still names the cards, so the grid code under it is unchanged.

In the same function, replace:

```swift
            VStack(spacing: SideBar.gap) {
                ForEach(rest) { tab in
                    SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active, pill: pill, close: {})
                }
            }
            newTab
```

with:

```swift
            if !pinsAsRows.isEmpty {
                VStack(spacing: SideBar.gap) {
                    ForEach(pinsAsRows) { tab in
                        SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active, pill: pill, close: {})
                    }
                }
                divider
            }
            VStack(spacing: SideBar.gap) {
                ForEach(rest) { tab in
                    SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active, pill: pill, close: {})
                }
            }
            newTab
```

- [ ] **Step 6: `SideRow`, kept**

In `private struct SideRow`, directly after `private var editing: Bool { browser.editingTab == tab.id }`, add:

```swift

    /// A pin, drawn as a row: its icon always, no cross — ⌘W or a
    /// middle-click puts it down — and in the cross's place, while it is
    /// away from its page, the way back.
    private var kept: Bool { tab.pin != nil }

    /// What sits at the row's end and takes the title's last few points: the
    /// cross under the pointer, or a pin's way back while it is away.
    private var endMark: Bool { kept ? tab.away : hovering }
```

Then make these replacements inside `SideRow`:

1. The mark, near the top of `body`. Replace `if prefs.glyph == .icons, !tab.isBlank {` with:
   ```swift
                   if prefs.glyph == .icons || kept, !tab.isBlank {
   ```

2. The status's place. Replace:
   ```swift
                   .opacity(hovering && !speaker ? 0 : 1)
                   .padding(.trailing, hovering && speaker ? 23 : 0)
   ```
   with:
   ```swift
                   .opacity(endMark && !speaker ? 0 : 1)
                   .padding(.trailing, endMark && speaker ? 23 : 0)
   ```

3. The mask. Replace:
   ```swift
                   Rectangle().opacity(hovering && !editing && !status ? 0 : 1)
   ```
   with:
   ```swift
                   Rectangle().opacity(endMark && !editing && !status ? 0 : 1)
   ```

4. The trailing overlay. Replace this whole block, from `.overlay(alignment: .trailing) {` down to (not including) the `.animation(Motion.quick, value: tab.loading)` line after it:
   ```swift
           .overlay(alignment: .trailing) {
               if !editing {
                   ZStack {
                       if hovering {
                           Image(systemName: "xmark")
                               .font(.system(size: 8, weight: .semibold))
                               .foregroundStyle(Palette.muted)
                               .frame(width: 15, height: 15)
                               .background(Palette.ink.opacity(0.07), in: Circle())
                               .transition(.opacity)
                       }
                   }
                   .frame(width: 15, height: 15)
                   .overlay {
                       Color.clear
                           .frame(width: 30, height: 28)
                           .contentShape(Rectangle())
                           .onTapGesture { if hovering { close() } }
                   }
                   .padding(.trailing, 7)
               }
           }
   ```
   with:
   ```swift
           .overlay(alignment: .trailing) {
               if !editing {
                   if kept {
                       if tab.away {
                           Image(systemName: "arrow.uturn.backward")
                               .font(.system(size: 8, weight: .semibold))
                               .foregroundStyle(Palette.muted)
                               .frame(width: 15, height: 15)
                               .background(Palette.ink.opacity(hovering ? 0.07 : 0), in: Circle())
                               .overlay {
                                   Color.clear
                                       .frame(width: 30, height: 28)
                                       .contentShape(Rectangle())
                                       .onTapGesture { browser.goHome(tab) }
                               }
                               .help("Back to Pinned Page")
                               .padding(.trailing, 7)
                               .transition(.opacity)
                       }
                   } else {
                       ZStack {
                           if hovering {
                               Image(systemName: "xmark")
                                   .font(.system(size: 8, weight: .semibold))
                                   .foregroundStyle(Palette.muted)
                                   .frame(width: 15, height: 15)
                                   .background(Palette.ink.opacity(0.07), in: Circle())
                                   .transition(.opacity)
                           }
                       }
                       .frame(width: 15, height: 15)
                       .overlay {
                           Color.clear
                               .frame(width: 30, height: 28)
                               .contentShape(Rectangle())
                               .onTapGesture { if hovering { close() } }
                       }
                       .padding(.trailing, 7)
                   }
               }
           }
           .animation(Motion.quick, value: tab.away)
   ```
   The existing `.animation(Motion.quick, value: tab.loading)` line stays right after it.

5. The click. Replace:
   ```swift
           .modifier(OneClick(double: false) {
               if live { browser.beginTabEdit(tab) } else { browser.select(tab) }
           })
   ```
   with:
   ```swift
           // A pin you are on is renamed with a double-click, as a card has its
           // letter changed; a tab you are on turns into its address.
           .modifier(OneClick(double: live && kept) {
               if !live { browser.select(tab) } else if kept { browser.beginTabRename(tab) } else { browser.beginTabEdit(tab) }
           })
   ```

- [ ] **Step 7: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then 32 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/Search/Side.swift
git commit -m "Pins are rows under the cards, with a line under them and a way back when they wander"
```

---

### Task 4: Bench, end-to-end check, changelog

**Files:**
- Modify: `Sources/Search/Bench.swift`: the `case "keep":` block, and the `"commands": [` list in the verb switch's final `default:`.
- Modify: `bench`: the `keep` usage line in the docstring, and the `keep` branch of request building.
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `Browser.keep(_:on:)`, `unpin(_:)`, `goHome(_:)`, and the `describe` fields `shelf`, `home` and `away` (PR 1).
- Produces: `./bench --test keep ID favorites|pins|off`.

- [ ] **Step 1: `keep` takes `pins`**

In `Bench.swift`, make the `switch request["as"]` inside `case "keep":` read exactly:

```swift
            switch request["as"] as? String ?? "" {
            case "favorites": browser.keep(tab, on: .favorites)
            case "pins": browser.keep(tab, on: .pins)
            case "off": browser.unpin(tab)
            default: answer(["error": "keep needs favorites, pins or off"]); return
            }
```

In the verb switch's final `default:`, add `"keep", "home",` to the `"commands": [` list, right after `"select",`.

In `bench`:
- replace the usage line that begins `    ./bench keep ID favorites|off` with:
  ```
      ./bench keep ID favorites|pins|off a tab made a favorite or a pin, moved between them, or let go — --test runs only
  ```
- in request building, replace:
  ```python
      elif verb == "keep":
          if len(args) != 2 or args[1] not in ("favorites", "off"): sys.exit("usage: bench keep ID favorites|off")
  ```
  with:
  ```python
      elif verb == "keep":
          if len(args) != 2 or args[1] not in ("favorites", "pins", "off"): sys.exit("usage: bench keep ID favorites|pins|off")
  ```

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, then 32 tests pass.

- [ ] **Step 2: Start the test run, with a server that has a slow page**

Write the test server. It's PR 1's server plus `/slow`, which answers after 3 seconds, and it's threaded so a slow request doesn't hold the others:

```bash
cat > /tmp/shelves-server.py <<'EOF'
import http.server, time
visits = {"home": 0}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow":
            time.sleep(3)
        if self.path == "/home":
            visits["home"] += 1
            if visits["home"] > 1:
                self.send_response(302); self.send_header("Location", "/inbox"); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers()
        self.wfile.write(f"<title>{self.path}</title><a id=out href='/elsewhere'>out</a>".encode())
    def log_message(self, *a): pass
class S(http.server.ThreadingHTTPServer): daemon_threads = True
S(("127.0.0.1", 8765), H).serve_forever()
EOF
nohup python3 /tmp/shelves-server.py >/dev/null 2>&1 & echo $! > /tmp/shelves-server.pid
D="$HOME/Library/Application Support/Search (test)"
cp "$D/session.json" "$D/session.json.before-pins" 2>/dev/null || true
nohup .build/debug/Search >/tmp/search-test.log 2>&1 &
sleep 3 && ./bench --test tabs
```

Expected: a tab listing, with no error. If the bench doesn't answer, the test world may need `defaults write com.officecommun.search.test bench -bool true` once. Set it and relaunch.

- [ ] **Step 3: Shelves in order, and moves between them**

```bash
A=$(./bench --test open http://127.0.0.1:8765/a) && ./bench --test wait $A
B=$(./bench --test open http://127.0.0.1:8765/b) && ./bench --test wait $B
C=$(./bench --test open http://127.0.0.1:8765/c) && ./bench --test wait $C
./bench --test keep $A favorites >/dev/null
./bench --test keep $B pins >/dev/null
./bench --test keep $C pins >/dev/null
./bench --test tabs
```

Expected: `FAV /a`, then `PIN /b`, then `PIN /c`, in that order, before any tab that isn't kept.

```bash
./bench --test keep $A pins >/dev/null && ./bench --test tabs
```

Expected: no FAV lines, then `PIN /a`, `PIN /b`, `PIN /c`. The favorite moved down is the first pin.

```bash
./bench --test keep $C favorites >/dev/null && ./bench --test tabs
./bench --test home $C
```

Expected: `FAV /c`, then `PIN /a`, `PIN /b`. The last pin moved up is the last favorite. The `home` answer still shows `"home": "http://127.0.0.1:8765/c"`.

```bash
./bench --test place $A 0; ./bench --test tabs
```

Expected: the order is unchanged (`FAV /c`, `PIN /a`, `PIN /b`). A pin can't be placed among the favorites. If `place` answers with an error instead, that's fine as long as the order is unchanged.

- [ ] **Step 4: A pin away and back, through a redirect**

```bash
H=$(./bench --test open http://127.0.0.1:8765/home) && ./bench --test wait $H
./bench --test keep $H pins
./bench --test go $H http://127.0.0.1:8765/elsewhere && ./bench --test wait $H
./bench --test home $H
./bench --test home $H go && ./bench --test wait $H
./bench --test home $H
```

Expected, in order:
1. After `keep`: `"shelf": "pins"` and `"home": ".../home"`.
2. After going elsewhere: `"away": true`.
3. After `home go`: `"url": "http://127.0.0.1:8765/inbox"` and `"away": false`. The second visit redirects, and the committed `/inbox` is where the trip landed.

- [ ] **Step 5: Back to Pinned Page while a slow page is loading**

```bash
./bench --test go $H http://127.0.0.1:8765/slow
./bench --test home $H go && ./bench --test wait $H
./bench --test home $H
```

Expected: `"url": "http://127.0.0.1:8765/inbox"` and `"away": false`. The slow load was cancelled by the trip home, and the trip still recognised its redirect.

To show the check has teeth, you can also:
1. build PR 1's head: `git worktree add /tmp/pr1 sidebar-shelves && (cd /tmp/pr1 && swift build)`;
2. repeat Steps 2, 4 and 5 against `/tmp/pr1/.build/debug/Search` (use `keep ID favorites`, since PR 1 has no pins);
3. `git worktree remove /tmp/pr1`.

On that build the last command may show `"away": true`. Record what you see either way; it's evidence, not a gate.

- [ ] **Step 6: The column: picture and drag area**

The drag-area check needs tabs down the side. If the test world shows them across the top, run `./bench --test ui sidebar on` first, and remember to run `./bench --test ui sidebar off` in Step 8.

With `A`, `B` and `H` as pins and `C` as a favorite, send `B` away:

```bash
./bench --test go $B http://127.0.0.1:8765/elsewhere && ./bench --test wait $B
./bench --test column /tmp/pins-column.png
```

Expected: the PNG shows, from the top:
1. one favorite card;
2. three full-width pin rows with icons (the monogram for 127.0.0.1), where `B`'s row has a ↩︎ at its end;
3. a thin line;
4. the other tabs as rows, then "New tab".

Record the path.

Check the drag area. `./bench hit X Y` takes points from the window's top left and answers whether a drag there moves the window. Step Y by 10 at X = 60:

```bash
for y in $(seq 40 10 400); do printf "%s " $y; ./bench --test hit 60 $y | tr -d '\n' | head -c 160; echo; done
```

Expected: every Y inside the rows (favorite card, pin rows, divider, tab rows, New tab) answers that a drag does **not** move the window. Below the last row, it does. The switch happens within about one row's height of the bottom of "New tab". Record the Y where it switches, and the number of rows.

- [ ] **Step 7: Pins survive a relaunch**

```bash
pkill -f "\.build/debug/Search"; sleep 1
cat > "$D/session.json" <<'EOF'
{"tabs":[
  {"url":"http://127.0.0.1:8765/f","title":"F","pin":"F","shelf":"favorites","home":"http://127.0.0.1:8765/f"},
  {"url":"http://127.0.0.1:8765/p1","title":"P1","pin":"P","shelf":"pins","home":"http://127.0.0.1:8765/p1"},
  {"url":"http://127.0.0.1:8765/elsewhere","title":"P2","pin":"Q","shelf":"pins","home":"http://127.0.0.1:8765/p2"},
  {"url":"http://127.0.0.1:8765/t","title":"T"}
],"active":3}
EOF
nohup .build/debug/Search >/tmp/search-test.log 2>&1 &
sleep 3 && ./bench --test tabs
```

Expected, in order:
1. `FAV F`
2. `PIN P1`
3. `PIN P2 … (away from http://127.0.0.1:8765/p2)`
4. `T` (active)

Then force a write and read it back:

```bash
P1=$(./bench --test tabs | awk '/PIN P1/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9a-f]{8}$/) {print $i; exit}}')
./bench --test keep $P1 pins >/dev/null
python3 -m json.tool "$D/session.json" | grep -E '"(url|shelf|home)"'
```

Expected: both pins still have `"shelf": "pins"` and their homes.

- [ ] **Step 8: Clean up**

```bash
./bench --test ui sidebar off   # only if Step 6 turned it on
pkill -f "\.build/debug/Search"; kill "$(cat /tmp/shelves-server.pid)"
[ -f "$D/session.json.before-pins" ] && mv "$D/session.json.before-pins" "$D/session.json"
pgrep -fl "\.build/debug/Search|shelves-server" || echo "clean"
```

Expected: `clean`.

- [ ] **Step 9: Changelog**

In `CHANGELOG.md`, under `## Unreleased` › `### Added`, add this as the first line of the list, above PR 1's favorites line:

```markdown
- Pins, as in Arc: rows under the favorite cards, with their titles, and a line between them and the day's tabs. Pin a tab from its menu; move it between favorites and pins the same way. A pin that has wandered off its page shows a way back at the end of its row, and a double-click renames the pin you're on.
```

- [ ] **Step 10: Commit**

```bash
git add Sources/Search/Bench.swift bench CHANGELOG.md
git commit -m "The bench can pin a tab, and the changelog says what pins are"
```

The controller pushes `sidebar-pins` and opens its PR after the final review:
`gh pr create --repo Richard-DEPIERRE/Search --base sidebar-shelves --head sidebar-pins`.
