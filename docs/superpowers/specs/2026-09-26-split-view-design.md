# Split view: two to four tabs side by side, ⌃⇧=

Date: 2026-09-26 · Branch: `split-view` (stacked on `peek-links`, #4) · Fork: `Richard-DEPIERRE/Search`

Sub-project C of the Arc features. Sub-project A (the sidebar shelves, #1–#3)
and B (Peek for cross-host links, #4) come before it in the stack.

## Goal

Show two to four tabs side by side in the one window, as full-height columns
with draggable dividers. ⌃⇧= opens a new pane.

A split is a lasting group:
- its tabs stay ordinary tabs in the sidebar, each wearing a small split mark;
- selecting any of them brings the whole split back, with that pane focused;
- it is saved with the session.

```
┌──────────┬─────────────────┬───┬─────────────────┐
│ sidebar  │  pane 1         │ ⋮ │  pane 2 (focus) │
│ ◫ Gmail  │                 │ ⋮ │ ╭─────────────╮ │
│ ◫ Notes  │                 │ ⋮ │ │             │ │
│   Tab    │                 │ ⋮ │ ╰─────────────╯ │
└──────────┴─────────────────┴───┴─────────────────┘
```

## Decisions made with the owner

| Question | Decision |
|---|---|
| What ⌃⇧= does | Adds a **blank pane to the right**: a new tab with its address field ready. |
| How many panes, and how they're arranged | **Up to 4, side by side**, as full-height columns. No grid. |
| What a split is | **A lasting group.** Its tabs stay separate rows with a split mark. Selecting any member shows the split. It's saved with the session. |
| Can favorites and pins be panes? | **Yes, any tab.** Members can sit in different parts of the sidebar, so a mark is used, not a bracket. |
| How it's stored | **A list of splits beside the tabs.** The flat tab list is unchanged. |

## Non-goals (v1)

- A grid, or rows of panes.
- Dragging panes to reorder them.
- Dropping a tab from the sidebar onto the page to split.
- A combined sidebar row per split.
- A tab in more than one split.
- Splits shared across spaces.

## 1. Model and saving

### `Splits.swift` (pure, Foundation only)

```swift
struct Split: Codable, Identifiable, Equatable {
    var id: UUID
    var tabs: [UUID]     // 2–4 tab ids, left to right
    var widths: [Double] // one fraction per pane; they sum to 1
}
```

The rules are pure functions over `[Split]`, and each one is unit-tested:

- **`adding(_ tab: UUID, beside: UUID, to: [Split]) -> [Split]?`**
  - If `beside` is in a split with fewer than 4 panes, `tab` is inserted directly to its right with a width of 1/n. The other panes are scaled by (n−1)/n.
  - If `beside` is in no split, a new split `[beside, tab]` is made at ½ and ½.
  - If `beside`'s split already has 4 panes, it returns `nil` and the caller beeps.
  - A `tab` that is already in a split leaves that split first.
- **`removing(_ tab: UUID, from: [Split]) -> [Split]`**
  - The removed pane's width is shared between its neighbours in proportion to their widths.
  - A split left with one pane dissolves.
- **`resizing(_ split: UUID, divider: Int, to fraction: Double, in: [Split]) -> [Split]`**
  - `fraction` is the divider's position across the whole split, from 0 to 1.
  - Only the two panes on either side of the divider change.
  - Each pane keeps at least `Splits.minimum = 0.12`.
- **`evened(_ split: UUID, in: [Split]) -> [Split]`** gives every pane 1/n. A double-click on a divider uses it.
- **`tidy(_ splits: [Split], existing: Set<UUID>) -> [Split]`** runs after every load and every tab close. It:
  - drops ids that are not in `existing`;
  - keeps a tab only in its first split;
  - dissolves splits with fewer than 2 panes and caps each split at 4, keeping the first 4;
  - repairs `widths` whose count is wrong, or which are not all finite and positive, by evening them;
  - otherwise renormalises the widths so they sum to 1, raising any below the minimum.
- **`split(containing tab: UUID, in: [Split]) -> Split?`**
- **Saving and restoring by position:**
  - `saved(_ splits: [Split], order: [UUID]) -> [SavedSplit]`
  - `restored(_ saved: [SavedSplit], order: [UUID]) -> [Split]`
  - `SavedSplit { tabs: [Int], widths: [Double] }`
  - `order` is the list of tabs in the order they are saved.
  - Positions that point at a tab that was not saved are dropped, and the result is tidied.

### Per space (`Browser`, `Spaces.swift`)

- `@Published var splits: [Split]`
- `var activeSplit: Split?` is the split that holds the active tab.
- `Parked` gains `splits`, and space switches carry them, as they do folders.

### On disk (`Session.Shape`)

- A new optional key: `"splits": [{ "tabs": [2, 5], "widths": [0.5, 0.5] }]`.
- `writeSession` computes the positions from the entries it actually writes. Tabs that are not written (private, bench, non-web) simply drop out of their split.
- On restore, the positions are mapped back to the restored tabs, then tidied.
- The key is decoded leniently: a broken `splits` entry, or a `splits` value that is not a list, is dropped on its own, never the whole session. This works like `folders`.
- Older builds ignore the key.

## 2. The page area, dividers and focus

- **Layout.**
  - When the active tab is in a split, the page area draws `SplitStage`: one `Page(tab:)` per member, left to right. Each pane is `widths[i] × (width − dividers)` wide.
  - Between panes there is a 6pt divider. Dragging it calls `resizing` and shows the ↔ cursor; a double-click calls `evened`.
  - Otherwise the page area is exactly as today.
- **Waking and sleeping.**
  - Showing a split wakes every member.
  - Members on screen count as looked at, so the idle sleep timer leaves them alone.
- **Focus.** The focused pane is the active tab. Every command that follows the active tab therefore follows the focused pane: ⌘L, ⌘W, reload, find, zoom, and the sidebar highlight.
  - A left mouse-down inside a pane's web view focuses that pane, through a local event monitor. It sets `activeID` without `select()`'s side effects (it doesn't close Peek or reorder anything), and makes the web view first responder.
  - The focused pane has a 1.5pt ring (`Palette.ink` at low opacity) along the page's rounded edge. The other panes are not dimmed.
- **Returning to a split.** Selecting a member in any way (the sidebar, ⌘1–9, ⌘K, ⌃Tab, the top bar) shows the split with that pane focused.
- **Page overlays** follow the focused pane: the find bar, the link-hover status line, the site card and the address field. Peek opens over the whole page area. A floating page (floating video) leaves its pane empty, as it leaves the page area empty today.
- **One web view in one place.** A tab is in at most one split, and Peek and the little window use tabs of their own, so no web view is drawn in two places.

## 3. Commands, closing and menus

- **⌃⇧=** (Tabs › New Split Pane; matched by key code 24 with ⌃⇧):
  - makes a blank tab at `placeForNew()`;
  - adds it with `adding(new, beside: active)`;
  - focuses it and opens its address field.
  - With 4 panes it beeps and does nothing else.
- **⌃⇧-** (Tabs › Remove from Split):
  - the focused tab leaves its split and stays open as an ordinary tab;
  - the others widen;
  - a split with one pane left ends.
- **⌘W or a middle-click on a pane.** The tab closes or is put down as today, and it also leaves its split. Focus goes to its left neighbour, or its right neighbour if it was first, instead of the usual most-recently-touched choice.
- **⌃⇧]** and **⌃⇧[** focus the next or previous pane of the split on screen.
- **A tab's right-click menu:**
  - **Add to Split** appears when the active tab's split has room, or the active tab is in no split, and the clicked tab isn't the active tab or already in that split. The clicked tab joins to the right of the focused pane.
  - **Remove from Split** appears when the clicked tab is in a split.
- **Leaving and coming back.** Selecting a tab outside the split shows that tab alone. The split stays saved and returns when one of its members is selected.
- **Reordering, closing and spaces.**
  - Reordering tabs in the sidebar or the top bar doesn't change a split's left-to-right order.
  - Tabs closed by an extension or by a page's own script leave their split through `tidy`.
  - Space switches carry each space's splits.

## 4. The split mark

- **Rows.** Today's-tab rows and pin rows in a split show `rectangle.split.2x1` (9pt, muted) before the title, next to the existing flask and private marks.
- **Favorite cards** show a small `rectangle.split.2x1` in their top-right corner. The away dot stays at the bottom.
- **The top bar.** Squares and pills in the top bar get the same mark.
- **Rows on screen.** The focused member has the normal highlight. The split's other members get a lighter version of it (`Palette.wash` at half opacity).

## 5. Testing

- **`SplitsTests`** cover adding, removing, resizing, evening, `tidy`, and saving and restoring by position. `SessionTests` cover the lenient `splits` decoding.
- **Bench** (test runs only):
  - `split new`, `split add ID`, `split remove ID`, `split focus ID`, `split resize I FRACTION`, `split even`;
  - `split list`, which reports the panes, their widths and the focused pane.
- **End to end:**
  - ⌃⇧= through the real key path (`bench press`), three times, then a fourth that is refused;
  - a real click in a pane moves focus (`bench tap`);
  - ⌘W on a pane (`bench press`) closes it, and focus moves to the neighbour;
  - leaving to another tab and coming back restores the split;
  - a relaunch restores the split and its widths;
  - a broken `splits` entry doesn't cost the session;
  - a picture of the whole window (`bench picture`), plus `bench column` for the marks.
- **The gate:** `swift build`, `swift test` and `./build.sh`, plus the owner's manual pass with real divider drags.

## 6. Delivery

- One PR from `split-view`, with base `peek-links`: `gh pr create --repo Richard-DEPIERRE/Search --base peek-links`.
- A changelog line. Never run `./ideas`. Comments are in the repo's voice, with no attribution lines.

## Risks

- **Focus by mouse monitor.** A click must reach the page as usual, and the focus change must not cost the page its click. Mitigation: the monitor only observes (it returns the event) and sets `activeID` without re-running `select()`.
- **Overlays tied to the stage.** The find bar and the status line are placed over "the stage" today, so each needs to know the focused pane's frame. Mitigation: the split stage publishes the focused pane's frame, and the overlays use it.
- **Web views moving between superviews.** Showing and hiding a split moves web views between one `StageView` and several. Mitigation: each `Page` still owns exactly one web view, and a tab is never in two panes.
