# A split as one row, and drag and drop between sections and into splits

Date: 2026-09-26 · Branches: `split-row` (PR 6, stacked on `split-view`, #5) and `drag-drop` (PR 7, stacked on `split-row`) · Fork: `Richard-DEPIERRE/Search`

This follows split view (#5). The owner asked for these before sub-project D
(passwords): "so that I don't have to right click", and "the split tabs to
be on one line in the sidebar … since it can be a bit confusing sometimes".

## Decisions made with the owner

| Question | Decision |
|---|---|
| Where a split's row sits | **Always among today's tabs.** Favorites and pins in the split keep their own card or row as well, with the ◫ mark. |
| Dragging into a split | **All three ways:** drop on the left or right half of the page; drop on a split's row; drag a pane's segment out of its row. |
| Dragging between sections | **All of these:** today's tab → favorites or pins; favorite ↔ pin; favorite or pin → today's tabs (unpin). |
| How it's built | **Extend the existing drag.** Live reorder within a section stays as it is. A drop is decided on release by a pure rule, `Drops.resolve`. |
| Dragging a whole split row up or down | **Not in v1.** A split's row sits where its tabs are. |
| Scope | **The sidebar only.** The horizontal tab bar (⇧⌘S) keeps today's behaviour, including the ◫ marks. |

## Non-goals (v1)

- Reordering a whole split by drag.
- Drag and drop in the horizontal tab bar.
- Macos's system drag and drop (`draggable`/`dropDestination`).
- Dropping links or files from other apps onto the sidebar in new ways. What exists today stays.
- Cancelling a drag with Escape. Letting go back where you started, or nowhere, does nothing.

---

## PR 6: a split as one row

### Keeping a split's tabs together

A pure rule keeps a split's *today's tabs* next to each other in `tabs`, the
same way a folder's pins are kept together:

```swift
/// Today's tabs of each split, gathered where the first of them is; every
/// other tab keeps its place. Kept tabs (favorites, pins) are never moved.
static func gathered(_ order: [UUID], loose: Set<UUID>, splits: [Split]) -> [UUID]
```

- It lives in `Splits.swift`.
- `Browser.tidyTabs()` applies it to the today's-tabs section, after the existing shelf tidy.
- It is called wherever `splits` changes membership, so after a split's tabs are added or removed.
- It is stable: gathering an order that is already gathered changes nothing.

### The row

- **Its place.** Among today's rows, a split is drawn as **one 28pt row** where its first today's tab is. A split made only of favorites and pins has its row at the top of today's tabs. Today's tabs that are in a split are not drawn as rows of their own.
- **Segments.** The row is split into **equal segments**, one per pane, left to right in pane order.
  - Each segment shows the page's icon and its label, truncated. A segment narrower than 60pt shows only the icon.
  - Thin vertical hairlines (`Palette.hairline`) separate the segments.
- **On screen.** When the split is on screen, the whole row gets the live highlight (`Palette.wash`), and the focused pane's segment gets `Palette.ink` at 0.06 on top.
- **Actions:**
  - A click on a segment runs `select(tab)`, which shows the split with that pane focused.
  - Hovering a segment shows ✕ at its trailing end. The ✕, or a middle-click on the segment, runs `close(tab)`: the tab closes, or a kept one is put down, and the split shrinks or ends as it does today.
  - Right-clicking a segment shows that tab's `TabMenu`, plus **Separate Split**, which removes every pane so the tabs come back as ordinary rows.
- **Favorites and pins in a split** keep their card or row in their own section, with the ◫ mark, and also appear as a segment.
- **Heights.** `rowsEnd` counts a combined row as one row; the today's tabs inside it don't add any height.
- **Space previews.** Another space's swipe preview draws its combined rows too, from `Parked.splits`.
- **Top bar.** It is unchanged.

### Testing (PR 6)

- **`SplitsTests`** for `gathered`:
  - a split's today's tabs are gathered at the first one's place;
  - kept tabs are left alone;
  - gathering twice changes nothing;
  - tabs that aren't in a split keep their order.
- **Bench:** `split list` also reports the drawn today's rows, with a combined row shown as `SPLIT a|c`, and `bench column` pictures it.
- **Owner's manual pass:** the row's look, clicks, ✕, middle-click and Separate Split.

---

## PR 7: drag and drop

### The drop rules (`Drops.swift`, pure, Foundation only)

```swift
enum Side: Equatable { case left, right }

enum DropTarget: Equatable {
    case favorites(Int)     // a slot among the favorite cards
    case pins(Int)          // a line among the pinned rows as drawn (folders included)
    case today(Int)         // a line among today's rows as drawn
    case splitRow(UUID)     // onto a split's combined row
    case page(Side)         // the left or right half of the page
}

enum DragSource: Equatable {
    case favorite, pin, today
    case pane(UUID)         // a segment dragged out of this split's row
}

enum DropAction: Equatable {
    case none
    case favorite(at: Int)
    case pin(at: Int)                      // then placed with Shelves.movePin's rules
    case unpin(at: Int)
    case joinSplit(UUID)                   // as its rightmost pane
    case splitPage(Side)                   // beside the focused page
    indirect case leaveSplitThen(DropAction)
}

static func resolve(source: DragSource, target: DropTarget?, tab: UUID, active: UUID?, splits: [Split]) -> DropAction
```

| Dragged | Dropped on | Action |
|---|---|---|
| Today's tab | `favorites(i)` | `.favorite(at: i)` |
| Today's tab or favorite | `pins(i)` | `.pin(at: i)`. The folder follows `Shelves.movePin`'s rules. |
| Pin | `favorites(i)` | `.favorite(at: i)`. The pin leaves its folder. |
| Favorite or pin | `today(i)` | `.unpin(at: i)` |
| Any tab not in that split | `splitRow(id)` | `.joinSplit(id)`, or `.none` when that split has 4 panes. |
| Any tab except the active one | `page(side)` | `.splitPage(side)`, or `.none` when the split on screen has 4 panes. |
| The active tab | `page(_)` | `.none` |
| `.pane(id)` | anywhere except its own split's row | `.leaveSplitThen(the action for that target, as if dragged from today's tabs)` |
| Anything | `nil`, or its own section | `.none` (the live reorder already applied) |

Additions to `Splits`:
- `adding(_:beside:onLeft:)`. The existing `adding(_:beside:to:)` becomes `onLeft: false`.
- `.splitPage(.left)` puts the tab left of the focused pane, and `.right` puts it to the right.
- When the active tab is in no split, the new split is `[tab, active]` for the left half or `[active, tab]` for the right, at halves.

### While dragging

- **Within a section,** a drag starts and reorders exactly as now, through `Carried` and the grid's reorder.
- **Leaving the section.** When the pointer leaves its section's frame, the section stops reordering (its rows settle back to where they started) and the tab is **lifted**:
  - a floating chip (the icon, the label and a soft shadow) follows the pointer, drawn in a window-level overlay;
  - `Browser.dragging: DragState?` holds `{ tab, source, point, target }`.
- **Drop areas.** Each area reports its frame in window coordinates (favorite grid, pinned rows, today's rows, each split row, the page area). The target under the pointer is computed from those frames and the rows' 28pt step.
- **Indicators:**
  - favorite cards: a 2pt vertical line at the slot;
  - pinned and today's rows: a 2pt horizontal line between rows, indented when the drop would go into a folder;
  - a split's row: a 1.5pt outline;
  - a page half: a tint (`Palette.ink` at 0.06) with a ◫ glyph. When the split on screen is full, there is no tint.
- **Letting go** applies `resolve`'s action through `Browser`, using `keep(_:on:)`, `unpin`, `movePinRow`, `move`, `addToSplit` and `removeFromSplit`, plus a new `Browser.splitPage(_ tab:, side:)`, all with the usual settle animation. The chip fades out.
- **Dragging a segment.** A drag that starts on a combined row's segment is the pane itself, and is lifted at once, since it has no section to reorder in.

### Testing (PR 7)

- **`DropsTests`** cover every row of the table, including:
  - a full split being refused;
  - the active tab dropped on the page;
  - a pane pulled out then dropped on today's rows, the pins, and the other half of the page;
  - `nil`.
- **`SplitsTests`** cover the left-side `adding`.
- **Bench:** `drop ID TARGET`, test runs only. It applies `resolve` and the action on the live instance, so the end-to-end check can drive every rule. The bench can't perform a real drag.
- **Owner's manual pass:** real drags from each section to each other, onto a split's row, onto both halves of the page, and a segment pulled out, with the chip and the indicators showing.

---

## Delivery

- PR 6: `split-row` → base `split-view`.
- PR 7: `drag-drop` → base `split-row`.
- Both use `gh pr create --repo Richard-DEPIERRE/Search`. Each has a changelog line. Never run `./ideas`. Comments are in the repo's voice, with no attribution lines.

## Risks

- **Gesture ownership.** The lifted drag keeps using the row's `DragGesture`. Its `onChanged` reports window positions, and its `onEnded` applies the drop. Mitigation: `Carried` gains one optional callback, and in-section behaviour stays exactly as it is.
- **The page's own drop handling.** It isn't involved, because no system drag session is started. The page never sees the drag.
- **Frames arriving a frame late.** Drop areas report their frames through preferences. Mitigation: targets are computed on each drag event from the latest frames, and the result applies only on release.
