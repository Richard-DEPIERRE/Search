# Sidebar: favorites, pinned rows, folders, and pins that remember their page

Date: 2026-09-25 · Branch: `sidebar-shelves` · Fork: `Richard-DEPIERRE/Search`

Sub-project A of the "Arc features" work. B (cross-site links from
favorites/pins open in Peek), C (split view, ⌃⇧=) and D (Apple passwords)
get their own specs after this one.

## Goal

Bring Arc's sidebar model to Search, per space:

```
┌───────────────────────────┐
│ [G] [M] [C] [F]           │  Favorites — icon/letter cards (today's pins)
│ ▸ 🗂 Work                  │  Pinned — full-width rows, one level of folders
│   ● Linear                │
│   ● Notion                │
│ ● Calendar             ↩︎  │  ← away from its pinned page
│ ───────────────────────── │  divider (only when there are pins)
│ ● Some article         ✕  │  Today's tabs
│ + New tab                 │
└───────────────────────────┘
```

Favorites and pins behave the same way. The only differences are how they
look and where they sit. Both remember the page they were kept at (`home`),
both go back to it, and both will send cross-site links to Peek (sub-project B).

## Decisions made with the owner

| Question | Decision |
|---|---|
| The model | Favorites (cards) → pinned rows with folders → divider → today's tabs. All per space. |
| What today's pins become | **Favorites.** They look exactly as now. The pinned rows start empty. |
| ⌘W on a favorite or pin that is away from its page | **Goes back to its page and sleeps** (Arc). |
| Rollout | **Replaces** today's layout. No setting. |
| Folder depth | **One level.** A folder holds pins, not other folders. |
| Storage approach | **Flat `tabs` list, with each tab tagged.** No separate tree. |
| Dragging between sections (for example dragging a tab above the divider to pin it) | **Not in v1.** Moving between sections is done from the menus. |
| Horizontal tab bar (⇧⌘S mode) | Favorites and pins are both squares, in order. Folders aren't shown there. |

## Non-goals

- Nested folders.
- Folders among favorites or among today's tabs.
- Drag-and-drop between favorites, pins and today's tabs.
- A keyboard shortcut for "Back to Pinned Page".
- Favorites or pins shared across spaces. Each space has its own, as pins do today.
- Updating ROADMAP.md with `./ideas`. It writes to the upstream owner's database.

## 1. Data and saving

### On a tab (`Tab.swift`)

- `pin: String?` is **unchanged**. It is still the letter drawn on a favorite
  square, and `pin != nil` still means *kept* (a favorite or a pin). Every
  existing check keeps its meaning: ⌘W puts the tab down, `placeForNew` never
  lands among kept tabs, the sleep rules, and so on.
- New `shelf: Shelf` (`enum Shelf: String, Codable { case favorites, pins }`).
  It only means something when `pin != nil`.
- New `home: URL?`. It is set to the current address when the tab is
  favorited or pinned, and cleared when it is released.
- New `landed: URL?`. This is the first address committed after a "go back
  to home", so a redirect on the way home still counts as home. It is not
  saved to disk.
- New `folder: UUID?`. It is only meaningful when `shelf == .pins`.

### Per space (`Browser`, `Spaces.swift`)

- New `@Published var folders: [Folder]`, where
  `struct Folder: Codable, Identifiable, Equatable { var id: UUID; var name: String; var open: Bool }`.
- `Parked` gains `folders`, so switching spaces swaps them along with the tabs.
  `enter` and `preloadSpaces` carry them. `leaveSpaces` and deleting a space
  treat them as they treat tabs.

### The order invariant

The `tabs` list is always:

```
[favorites…] [pins…, each folder's pins next to each other] [today's tabs…]
```

- A folder's position in the pinned section is where its pins are.
- A folder exists only while it holds at least one pin. It is created with
  "New Folder with This Pin", and deleted when its last pin leaves.
- `tidy()` runs after every change that affects it and after every load. It:
  1. keeps favorites, pins and today's tabs in that order, keeping their relative order within each section;
  2. clears the `folder` of any tab that isn't a pin, or whose folder id doesn't exist;
  3. gathers each folder's pins together at the position of its first pin;
  4. deletes folders that have no pins.

  A hand-edited or half-written file therefore repairs itself and never breaks
  the column.

### On disk (`Session.swift`)

Everything new is optional, so older files still read:

```swift
struct Entry: Codable {
    var url: String
    var title: String
    var pin: String?
    var name: String?
    var shelf: String?    // "favorites" | "pins"; nil + pin → favorites
    var home: String?     // nil + pin → url
    var folder: String?   // a Folder.id, pins only
}
struct Shape: Codable {
    var tabs: [Entry]
    var active: Int
    var folders: [Folder]?
}
```

Migration happens when a file is read:
- `pin != nil` with no `shelf` becomes a favorite.
- `pin != nil` with no `home` gets `home = url`.

An older build reading a newer file ignores the keys it doesn't know and
sees every kept tab as a pin. Nothing is lost.

## 2. Sidebar views and dragging (`Side.swift`)

From top to bottom:

1. **Favorites.** The existing `PinGrid` and `PinSquare`, fed with
   favorites only. The column count, sizing, letter/icon (`prefs.glyph`),
   drag-to-reorder and double-click to change the letter are all unchanged.
2. **Pinned.** A new list of 28pt rows (`SideBar.row`), so every row is the
   same height and `Carried` can do the dragging:
   - **Pin row.** Site icon and `label`, drawn like a `SideRow`. It has no
     close ✕; the ↩︎ back button is shown when the tab is away (§3).
     Double-click renames it (the existing rename field). Right-click opens the
     shared `TabMenu`.
   - **Folder row.** Chevron, folder icon and name. A click opens or closes
     it, which is saved. A double-click renames it. Right-click offers
     Rename Folder / Delete Folder.
   - **Pins inside a folder** are indented by about 14pt and hidden while the
     folder is closed. The exception: if the active tab is in a closed
     folder, it stays visible under the folder row.
3. **Divider.** A thin rule, drawn only when there are pins.
4. **Today's tabs** and **New tab**, as now. Their drag offset becomes
   `+ keptCount` instead of `+ pinnedCount`.

### Dragging inside the pinned section

The list being dragged is the rows you can see: folder rows plus the pins on
show.

- **Reordering a pin.** Where it ends up decides its folder:
  - between two pins of a folder (or directly under an open folder's row): it joins that folder;
  - above a folder row, or below that folder's last pin: it leaves the folder.
- **Holding a pin over a folder row** for about 0.5s and letting go adds it
  to the end of that folder. A closed folder opens.
- **Dragging a folder row** moves the whole folder with its pins.
- `Browser.move` still refuses to cross sections.

### Other places to update

- **`rowsEnd`**, the hand-counted height where the window's drag area starts, adds the pinned rows and the divider.
- **The space-swipe `preview(_:)`** draws the same three blocks, not clickable.
- **`TabBar.swift`**, the horizontal bar, needs no layout change. Kept tabs are
  squares already, drawn in order with folders flattened.
- **⌘1–⌘9, ⌃Tab and ⌘K** go through `tabs` in order: favorites → pins
  (folders flattened) → today's tabs.

### Menu actions

These go in `TabMenu` and in the menu bar (`App.swift`, Tabs menu):

| Tab is | Actions |
|---|---|
| Today's tab | Add to Favorites · Pin |
| Favorite | Change Letter · Move to Pins · Remove from Favorites |
| Pin | Move to Favorites · New Folder with This Pin · Remove from Folder (when in one) · Unpin |
| Favorite or pin | Back to Pinned Page (when away) · Set Pinned Page to This Page |
| Folder row | Rename Folder · Delete Folder (its pins become loose pins) |

"Add to Favorites" puts the tab at the end of the favorites. "Pin" puts it at
the end of the pins, outside any folder.

## 3. Pins that remember their page

### When a tab is "away"

`away` is true when the tab is kept, has a `home`, and its current address is
neither `home` nor `landed`.

Addresses are compared after normalising: the `#fragment` is dropped and a
trailing `/` on the path is dropped. The scheme, host, path and query must
then match exactly.

### What you see

- **Pin row, away.** The label is the current page's title, and a ↩︎ button
  sits where a tab's ✕ would be. Clicking it loads `home` in place, keeping the
  tab awake, and clears `landed` so the next commit sets it.
- **Favorite square, away.** A small dot under the square. Going back is done
  from the menu.

### Actions

- **⌘W on a kept tab.** As `rest()` does now, but `pending` becomes `home`
  (falling back to `address` if there is no `home`). Then it selects a tab
  exactly as today.
- **Back to Pinned Page.** Loads `home` in the tab.
- **Set Pinned Page to This Page.** `home = address` and `landed = nil`.
- **Unpin, or Remove from Favorites.** `home = nil`, `landed = nil`,
  `folder = nil`. The tab stays on its current page.
- **Duplicate.** Makes a regular tab at the current address.

### Saving and relaunching

- A kept tab that is asleep is saved at `pending`, which is `home` after a ⌘W.
- A kept tab that is open and away is saved at its current address, with
  `home` stored alongside. After a relaunch it is still away, so the ↩︎ shows.

## 4. Testing

- **Pure logic in `Shelves.swift`**, with no WebKit or SwiftUI. It works
  on a lightweight value (`Slot { id, pin: Bool, shelf, folder }`) and provides:
  - section boundaries;
  - `tidy`;
  - move targets, including joining and leaving folders;
  - `putInFolder`;
  - the away comparison: `normalised(_:)` and `isHome(address:home:landed:)`.

  `Browser` calls into it and applies the result to `tabs`.
- **New test target `Tests/SearchTests`.** It uses Swift Testing and
  `@testable import Search`, and is added to `Package.swift`. It covers:
  - **Migration:** an old `Shape` with pins becomes favorites with `home = url`;
    a new `Shape` survives encoding and decoding unchanged.
  - **`tidy`:** empty folders are deleted, unknown folder ids are dropped,
    scattered pins are gathered, and sections are put back in order.
  - **Moves:** nothing crosses a section; the join and leave boundaries of a folder work.
  - **Away:** a `#fragment` or trailing `/` alone isn't away; `landed` counts as
    home; a different path or query is away.
- **Bench** (`Bench.swift` plus `./bench`, test runs only): new commands
  `favorite ID`, `pin ID`, `folder ID NAME`, `home ID` and `away ID`. Tab
  listings mark `FAV`, `PIN`, the folder name and `AWAY`. `./bench column`
  PNGs check the layout; before/after shots are attached to each PR.
- **The gate before any PR:** `swift build`, `swift test` and `./build.sh` all
  pass. Then a manual pass in the built app: migrating an existing session,
  dragging into and out of folders, ⌘W on an away pin, relaunching, and
  switching spaces.

## 5. Delivery

Each PR has its own branch and goes to `Richard-DEPIERRE/Search`, base `main`,
always with `gh pr create --repo Richard-DEPIERRE/Search`. Each adds a line
to `CHANGELOG.md`. Commits follow the repo's plain-sentence style.

1. **PR 1: the model, migration, and going back to the pinned page.**
   `shelf`, `home`, `landed`, `folder`, `Folder`, `Shelves.swift`, the Session
   migration, the test target, away detection, ⌘W going home, the favorite
   dot, and the Back / Set Pinned Page actions. Visually, pins become
   favorites and look exactly as today.
2. **PR 2: pinned rows.** The rows section, divider, Move to Favorites/Pins,
   `rowsEnd`, the space preview, the pin-row ↩︎ button, and the bench commands.
3. **PR 3: folders.** Folder rows, open and closed, dragging in and out,
   moving a whole folder, the folder menu, and the space preview for folders.

## Risks

- **`rowsEnd` is hand-counted.** Any mismatch lets the window drag from a
  row, or stops a row from being clickable. Mitigation: a single function
  computes the height of the pinned section, used by both the view and `rowsEnd`.
- **Drag state across rows of different kinds** (folder rows and pin rows).
  Mitigation: every row is the same 28pt height, and targets are computed by
  the pure `Shelves` functions, which the tests cover.
- **Merging upstream later** will conflict in `Side.swift`, `Browser.swift` and
  `TabMenu`. This is accepted, since the new layout replaces the old one.
