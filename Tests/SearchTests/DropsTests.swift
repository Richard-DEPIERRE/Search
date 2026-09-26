import Foundation
import Testing
@testable import Search

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 0.0001 } }
private let onScreen = UUID(uuidString: "5B000000-0000-0000-0000-00000000000A")!
private let full = UUID(uuidString: "5B000000-0000-0000-0000-00000000000B")!
private let other = UUID(uuidString: "5B000000-0000-0000-0000-00000000000C")!
/// Tab 1 is the one you are on, in a split with 2; 5–8 fill a split; 3 and
/// 4 make another; 9 is in none.
private let splits = [
    Split(id: onScreen, tabs: [id(1), id(2)], widths: [0.5, 0.5]),
    Split(id: full, tabs: [id(5), id(6), id(7), id(8)], widths: [0.25, 0.25, 0.25, 0.25]),
    Split(id: other, tabs: [id(3), id(4)], widths: [0.5, 0.5]),
]
private func drop(_ source: DragSource, _ target: DropTarget?, _ tab: Int, active: Int? = 1) -> DropAction {
    Drops.resolve(source: source, target: target, tab: id(tab), active: active.map(id), splits: splits)
}

@Suite struct DropsResolveTests {
    @Test func aTodaysTabGoesToTheFavoritesOrThePins() {
        #expect(drop(.today, .favorites(2), 9) == .favorite(at: 2))
        #expect(drop(.today, .pins(1), 9) == .pin(at: 1))
    }

    @Test func aFavoriteGoesToThePinsAndAPinToTheFavorites() {
        #expect(drop(.favorite, .pins(0), 9) == .pin(at: 0))
        #expect(drop(.pin, .favorites(3), 9) == .favorite(at: 3))
    }

    @Test func aKeptTabDroppedAmongTodaysIsLetGo() {
        #expect(drop(.favorite, .today(3), 9) == .unpin(at: 3))
        #expect(drop(.pin, .today(0), 9) == .unpin(at: 0))
    }

    @Test func inItsOwnSectionOrNowhereNothingMore() {
        #expect(drop(.today, .today(1), 9) == DropAction.none)
        #expect(drop(.favorite, .favorites(1), 9) == DropAction.none)
        #expect(drop(.pin, .pins(1), 9) == DropAction.none)
        #expect(drop(.today, nil, 9) == DropAction.none)
    }

    @Test func onASplitsRowItJoinsIt() {
        #expect(drop(.today, .splitRow(other), 9) == .joinSplit(other))
        #expect(drop(.favorite, .splitRow(onScreen), 9) == .joinSplit(onScreen))
    }

    @Test func aFullSplitOrItsOwnTakesNoMore() {
        #expect(drop(.today, .splitRow(full), 9) == DropAction.none)
        #expect(drop(.today, .splitRow(other), 3) == DropAction.none)
    }

    @Test func onAHalfOfThePageItMakesASplit() {
        #expect(drop(.today, .page(.left), 9) == .splitPage(.left))
        #expect(drop(.pin, .page(.right), 9) == .splitPage(.right))
    }

    @Test func theTabOnScreenOrAFullSplitOnScreenRefusesThePage() {
        #expect(drop(.today, .page(.left), 1) == DropAction.none)
        #expect(drop(.today, .page(.left), 9, active: 5) == DropAction.none)
        #expect(drop(.today, .page(.left), 6, active: 5) == .splitPage(.left))
        #expect(drop(.today, .page(.left), 9, active: nil) == DropAction.none)
    }

    @Test func aPaneLeavesItsSplitForASection() {
        #expect(drop(.pane(split: onScreen, was: .today), .pins(1), 2) == .leaveSplitThen(.pin(at: 1)))
        #expect(drop(.pane(split: onScreen, was: .favorite), .today(2), 2) == .leaveSplitThen(.unpin(at: 2)))
    }

    @Test func aPaneBackInItsOwnSectionIsPlaced() {
        #expect(drop(.pane(split: onScreen, was: .today), .today(0), 2) == .leaveSplitThen(.place(at: 0)))
        #expect(drop(.pane(split: onScreen, was: .pin), .pins(4), 2) == .leaveSplitThen(.place(at: 4)))
    }

    @Test func aPaneMovesToTheOtherHalfOrAnotherSplit() {
        #expect(drop(.pane(split: onScreen, was: .today), .page(.left), 2) == .splitPage(.left))
        #expect(drop(.pane(split: onScreen, was: .today), .splitRow(other), 2) == .joinSplit(other))
        #expect(drop(.pane(split: other, was: .today), .page(.right), 3) == .splitPage(.right))
    }

    @Test func aPaneOnItsOwnRowOrNowhereStays() {
        #expect(drop(.pane(split: onScreen, was: .today), .splitRow(onScreen), 2) == DropAction.none)
        #expect(drop(.pane(split: onScreen, was: .today), nil, 2) == DropAction.none)
        #expect(drop(.pane(split: onScreen, was: .today), .page(.left), 1) == DropAction.none)
    }
}

@Suite struct SplitAddLeftTests {
    @Test func onTheLeftOfATabInNoSplitComesFirst() {
        let out = Splits.adding(id(2), beside: id(1), onLeft: true, to: [])!
        #expect(out.count == 1)
        #expect(out[0].tabs == [id(2), id(1)])
        #expect(near(out[0].widths, [0.5, 0.5]))
    }

    @Test func onTheLeftInsideASplitGoesBeforeIt() {
        let out = Splits.adding(id(3), beside: id(2), onLeft: true, to: [Split(id: onScreen, tabs: [id(1), id(2)], widths: [0.5, 0.5])])!
        #expect(out[0].tabs == [id(1), id(3), id(2)])
        #expect(near(out[0].widths, [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }
}
