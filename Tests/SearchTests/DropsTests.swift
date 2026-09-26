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

private let rowSplit = UUID(uuidString: "5B000000-0000-0000-0000-00000000000D")!
private let folderID = UUID(uuidString: "5F000000-0000-0000-0000-000000000001")!
/// Three favorites in a row of three, two pinned rows, three of today's rows
/// with a split as the second, then the page right of the column.
private var areas: DropAreas {
    var a = DropAreas()
    a.favorites = CGRect(x: 10, y: 50, width: 120, height: 34)
    a.favoriteColumns = 3
    a.favoriteStep = CGSize(width: 40, height: 38)
    a.favoriteCount = 3
    a.pins = CGRect(x: 10, y: 100, width: 200, height: 60)
    a.pinCount = 2
    a.today = CGRect(x: 10, y: 170, width: 200, height: 122)
    a.todayCount = 3
    a.splitRows = [rowSplit: CGRect(x: 10, y: 200, width: 200, height: 28)]
    a.page = CGRect(x: 240, y: 0, width: 800, height: 600)
    return a
}

@Suite struct DropAreaTests {
    @Test func aPointInTheFavoritesIsASlot() {
        #expect(Drops.target(at: CGPoint(x: 15, y: 60), in: areas) == .favorites(0))
        #expect(Drops.target(at: CGPoint(x: 75, y: 60), in: areas) == .favorites(2))
        #expect(Drops.target(at: CGPoint(x: 125, y: 60), in: areas) == .favorites(3))
    }

    @Test func anEmptyFavoritesWellIsSlotZero() {
        var a = DropAreas()
        a.favorites = CGRect(x: 10, y: 50, width: 200, height: 34)
        #expect(Drops.target(at: CGPoint(x: 100, y: 60), in: a) == .favorites(0))
    }

    @Test func aPointInThePinsIsALine() {
        #expect(Drops.target(at: CGPoint(x: 50, y: 101), in: areas) == .pins(0))
        #expect(Drops.target(at: CGPoint(x: 50, y: 125), in: areas) == .pins(1))
        #expect(Drops.target(at: CGPoint(x: 50, y: 158), in: areas) == .pins(2))
    }

    @Test func theMiddleOfASplitsRowIsTheRowItsEdgesALine() {
        #expect(Drops.target(at: CGPoint(x: 50, y: 214), in: areas) == .splitRow(rowSplit))
        #expect(Drops.target(at: CGPoint(x: 50, y: 202), in: areas) == .today(1))
    }

    @Test func belowTheLastRowIsTheEnd() {
        #expect(Drops.target(at: CGPoint(x: 50, y: 285), in: areas) == .today(3))
    }

    @Test func thePageIsHalves() {
        #expect(Drops.target(at: CGPoint(x: 300, y: 300), in: areas) == .page(.left))
        #expect(Drops.target(at: CGPoint(x: 900, y: 300), in: areas) == .page(.right))
    }

    @Test func nowhereIsNil() {
        #expect(Drops.target(at: CGPoint(x: 5, y: 5), in: areas) == nil)
    }

    @Test func aTabLeavesItsSectionOutsideItOrOverAnotherSplitsRow() {
        let row = [Split(id: rowSplit, tabs: [id(3), id(4)], widths: [0.5, 0.5])]
        #expect(Drops.isOut(id(9), from: .today, at: CGPoint(x: 50, y: 214), home: areas.today, areas: areas, splits: row))
        #expect(Drops.isOut(id(9), from: .today, at: CGPoint(x: 50, y: 60), home: areas.today, areas: areas, splits: row))
        #expect(Drops.isOut(id(3), from: .pane(split: rowSplit, was: .today), at: CGPoint(x: 50, y: 180), home: nil, areas: areas, splits: row))
    }

    @Test func insideItsSectionOrOverItsOwnSplitItStays() {
        let row = [Split(id: rowSplit, tabs: [id(3), id(4)], widths: [0.5, 0.5])]
        #expect(!Drops.isOut(id(9), from: .today, at: CGPoint(x: 50, y: 180), home: areas.today, areas: areas, splits: row))
        #expect(!Drops.isOut(id(3), from: .today, at: CGPoint(x: 50, y: 214), home: areas.today, areas: areas, splits: row))
        #expect(!Drops.isOut(id(9), from: .pin, at: CGPoint(x: 50, y: 125), home: areas.pins, areas: areas, splits: row))
    }
}

@Suite struct PinLineTests {
    let rows: [PinnedRow] = [.folder(folderID), .pin(id(1), folder: folderID), .pin(id(2), folder: folderID), .pin(id(3), folder: nil)]

    @Test func underAnOpenFolderOrBetweenItsPinsIsInIt() {
        #expect(Drops.pinLineFolder(rows, at: 1, open: [folderID]) == folderID)
        #expect(Drops.pinLineFolder(rows, at: 2, open: [folderID]) == folderID)
    }

    @Test func pastAClosedFolderOrAfterItsLastPinIsLoose() {
        #expect(Drops.pinLineFolder(rows, at: 0, open: [folderID]) == nil)
        #expect(Drops.pinLineFolder(rows, at: 3, open: [folderID]) == nil)
        #expect(Drops.pinLineFolder(rows, at: 4, open: [folderID]) == nil)
        #expect(Drops.pinLineFolder([.folder(folderID)], at: 1, open: []) == nil)
    }
}
