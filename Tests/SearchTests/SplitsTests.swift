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

    @Test func aTabBesideItselfIsRefused() {
        #expect(Splits.adding(id(1), beside: id(1), to: []) == nil)
    }

    @Test func addingKeepsEveryPaneAtTheMinimum() {
        let out = Splits.adding(id(4), beside: id(1), to: [split([1, 2, 3], [0.12, 0.12, 0.76])])!
        #expect(out[0].tabs.count == 4)
        #expect(out[0].widths.allSatisfy { $0 >= Splits.minimum - 1e-9 })
        #expect(abs(out[0].widths.reduce(0, +) - 1) < 0.0001)
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

    @Test func aSwappedTabKeepsItsPlace() {
        let out = Splits.replacing(id(2), with: id(7), in: [split([1, 2, 3], [0.3, 0.4, 0.3])])
        #expect(out[0].tabs == [id(1), id(7), id(3)])
        #expect(near(out[0].widths, [0.3, 0.4, 0.3]))
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

    @Test func twoNarrowPanesNeverGoNegative() {
        let out = Splits.resizing(splitID, divider: 0, to: 0.5, in: [split([1, 2, 3], [0.05, 0.1, 0.85])])
        #expect(out[0].widths.allSatisfy { $0 >= 0 })
        #expect(abs(out[0].widths.reduce(0, +) - 1) < 0.0001)
        #expect(near([out[0].widths[2]], [0.85]))
    }

    @Test func aDragWithNoPlaceIsIgnored() {
        let before = [split([1, 2, 3], [0.4, 0.3, 0.3])]
        let out = Splits.resizing(splitID, divider: 0, to: .nan, in: before)
        #expect(out == before)
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

    @Test func tidyingTwiceChangesNothing() {
        let once = Splits.tidy([split([1, 2, 3], [0.05, 0.5, 0.45])], existing: [id(1), id(2), id(3)])
        let twice = Splits.tidy(once, existing: [id(1), id(2), id(3)])
        #expect(near(once[0].widths, twice[0].widths))
        #expect(abs(once[0].widths[0] - Splits.minimum) < 0.0001)
        #expect(abs(once[0].widths.reduce(0, +) - 1) < 0.0001)
    }

    @Test func everyPaneEndsAtTheMinimumOrMore() {
        let out = Splits.tidy([split([1, 2, 3, 4], [0.01, 0.33, 0.33, 0.33])], existing: Set((1...4).map(id)))
        #expect(out[0].widths.allSatisfy { $0 >= Splits.minimum - 1e-9 })
        #expect(abs(out[0].widths.reduce(0, +) - 1) < 0.0001)
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

    @Test func missingWidthsAreEvenedNotDropped() {
        let out = Splits.restored([SavedSplit(tabs: [0, 1, 2], widths: [0.5, 0.5])], order: [id(1), id(2), id(3)])
        #expect(out.count == 1)
        #expect(out[0].tabs == [id(1), id(2), id(3)])
        #expect(near(out[0].widths, [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func aNegativePlaceDrops() {
        let out = Splits.restored([SavedSplit(tabs: [-1, 0, 1], widths: [0.3, 0.3, 0.4])], order: [id(1), id(2)])
        #expect(out.count == 1)
        #expect(out[0].tabs == [id(1), id(2)])
    }
}

private let otherSplitID = UUID(uuidString: "5B000000-0000-0000-0000-000000000002")!

@Suite struct TodayRowsTests {
    @Test func aSplitIsOneRowWhereItsFirstTodaysTabIs() {
        let rows = Splits.todayRows([id(1), id(2), id(3), id(4)], splits: [split([2, 4], [0.5, 0.5])])
        #expect(rows == [.tab(id(1)), .split(splitID), .tab(id(3))])
    }

    @Test func aSplitOfKeptTabsOnlyIsAtTheTop() {
        let kept = Split(id: otherSplitID, tabs: [id(7), id(8)], widths: [0.5, 0.5])
        let rows = Splits.todayRows([id(1), id(2)], splits: [kept])
        #expect(rows == [.split(otherSplitID), .tab(id(1)), .tab(id(2))])
    }

    @Test func noSplitsIsJustTheTabs() {
        #expect(Splits.todayRows([id(1), id(2)], splits: []) == [.tab(id(1)), .tab(id(2))])
    }
}

@Suite struct GatheredTests {
    let order = [id(9), id(1), id(2), id(3), id(4)]
    let loose: Set<UUID> = [id(1), id(2), id(3), id(4)]

    @Test func aSplitsTodaysTabsComeTogetherWhereTheFirstIs() {
        #expect(Splits.gathered(order, loose: loose, splits: [split([2, 4], [0.5, 0.5])]) == [id(9), id(1), id(2), id(4), id(3)])
    }

    @Test func theyGatherInTheOrderTheyStandNotPaneOrder() {
        #expect(Splits.gathered(order, loose: loose, splits: [split([4, 2], [0.5, 0.5])]) == [id(9), id(1), id(2), id(4), id(3)])
    }

    @Test func keptTabsAreNeverMoved() {
        let mixed = [id(7), id(1), id(2), id(3)]
        #expect(Splits.gathered(mixed, loose: [id(1), id(2), id(3)], splits: [split([7, 3], [0.5, 0.5])]) == mixed)
    }

    @Test func gatheringTwiceChangesNothing() {
        let once = Splits.gathered(order, loose: loose, splits: [split([2, 4], [0.5, 0.5])])
        #expect(Splits.gathered(once, loose: loose, splits: [split([2, 4], [0.5, 0.5])]) == once)
    }
}

@Suite struct MoveTodayTests {
    // Today's rows as drawn: 0 tab 1, 1 split (2, 4), 2 tab 3.
    let loose = [id(1), id(2), id(4), id(3)]
    let splits = [split([2, 4], [0.5, 0.5])]

    @Test func aTabMovesToTheRowTheHandIsOn() {
        #expect(Splits.moveToday(id(3), toRow: 0, loose: loose, splits: splits) == [id(3), id(1), id(2), id(4)])
    }

    @Test func aTabMovesPastASplitsRowWhole() {
        #expect(Splits.moveToday(id(1), toRow: 1, loose: loose, splits: splits) == [id(2), id(4), id(1), id(3)])
    }

    @Test func aSplitsTabOrNowhereChangesNothing() {
        #expect(Splits.moveToday(id(2), toRow: 0, loose: loose, splits: splits) == loose)
        #expect(Splits.moveToday(id(1), toRow: 9, loose: loose, splits: splits) == loose)
    }
}
