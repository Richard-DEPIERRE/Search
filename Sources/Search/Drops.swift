import Foundation

// A tab carried out of its section in the column and let go somewhere else:
// what that does, decided here, away from the gestures, so every case can be
// tested. The column and the page say where the hand is (DropTarget); the
// browser carries out the answer (Browser.apply).

enum Side: Equatable {
    case left, right
}

/// Where a carried tab is let go. The numbers are lines among that section's
/// rows as drawn, before the carried tab is taken out: 0 is before the first
/// row, the count is after the last.
enum DropTarget: Equatable {
    case favorites(Int)
    case pins(Int)
    case today(Int)
    case splitRow(UUID)
    case page(Side)
}

/// Where a carried tab came from: a section, or a split's row — a segment
/// pulled out of it, and what that pane is when it isn't a pane.
enum DragSource: Equatable {
    case favorite, pin, today
    indirect case pane(split: UUID, was: DragSource)
}

enum DropAction: Equatable {
    case none
    case favorite(at: Int)
    case pin(at: Int)
    case unpin(at: Int)
    /// Back in its own section at that line — only ever after leaving a split,
    /// since a section's own drag already places a tab that never left.
    case place(at: Int)
    /// As the split's rightmost pane.
    case joinSplit(UUID)
    /// Beside the pane you are on, on that side.
    case splitPage(Side)
    indirect case leaveSplitThen(DropAction)
}

enum Drops {
    /// What letting go of `tab` does. `active` is the tab you are on, whose
    /// split is the one on screen.
    static func resolve(source: DragSource, target: DropTarget?, tab: UUID, active: UUID?, splits: [Split]) -> DropAction {
        guard let target else { return .none }
        switch target {
        case .splitRow(let id):
            guard let split = splits.first(where: { $0.id == id }), !split.tabs.contains(tab), split.tabs.count < Splits.most else {
                return .none
            }
            return .joinSplit(id)
        case .page(let side):
            // The page you are on can't be dropped beside itself; a full split
            // on screen takes no more, though one of its own panes can move.
            guard let active, active != tab else { return .none }
            if let shown = Splits.split(containing: active, in: splits), !shown.tabs.contains(tab), shown.tabs.count >= Splits.most {
                return .none
            }
            return .splitPage(side)
        case .favorites(let at), .pins(let at), .today(let at):
            guard case .pane(_, let was) = source else { return shelved(source, target) }
            // Out of the split first, then as if carried from its section —
            // and back in that section, to where it was let go.
            let then = shelved(was, target)
            return .leaveSplitThen(then == .none ? .place(at: at) : then)
        }
    }

    /// A tab from one section let go in another. In its own, the section's
    /// live reorder has already put it where the hand is.
    private static func shelved(_ source: DragSource, _ target: DropTarget) -> DropAction {
        switch (source, target) {
        case (.favorite, .favorites), (.pin, .pins), (.today, .today): return .none
        case (_, .favorites(let at)): return .favorite(at: at)
        case (_, .pins(let at)): return .pin(at: at)
        case (_, .today(let at)): return .unpin(at: at)
        default: return .none
        }
    }
}
