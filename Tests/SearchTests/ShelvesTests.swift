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

    @Test func aFolderListedTwiceIsKeptOnce() {
        let row = [slot(1, kept: true, .pins, folder: work.id), slot(2, kept: true, .pins, folder: work.id)]
        let (out, folders) = Shelves.tidy(row, folders: [work, work])
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

@Suite struct SavedAddressTests {
    let home = URL(string: "https://mail.example.com/")!
    let landed = URL(string: "https://mail.example.com/mail/u/0/")!
    let elsewhere = URL(string: "https://mail.example.com/settings")!

    @Test func awakeWhereTheTripHomeLandedIsSavedAtHome() {
        #expect(Shelves.savedAddress(address: landed, home: home, kept: true, asleep: false, away: false) == home)
    }

    @Test func awayIsSavedWhereItIs() {
        #expect(Shelves.savedAddress(address: elsewhere, home: home, kept: true, asleep: false, away: true) == elsewhere)
    }

    @Test func asleepIsSavedWhereItWasPutDown() {
        #expect(Shelves.savedAddress(address: landed, home: home, kept: true, asleep: true, away: false) == landed)
    }

    @Test func aTabNotKeptIsSavedWhereItIs() {
        #expect(Shelves.savedAddress(address: landed, home: home, kept: false, asleep: false, away: false) == landed)
    }

    @Test func noHomeIsSavedWhereItIs() {
        #expect(Shelves.savedAddress(address: landed, home: nil, kept: true, asleep: false, away: false) == landed)
    }
}

@Suite struct CanBeHomeTests {
    @Test func aWebPageOrAFileCanBeHome() {
        #expect(Shelves.canBeHome(URL(string: "http://a.com/")))
        #expect(Shelves.canBeHome(URL(string: "https://a.com/x")))
        #expect(Shelves.canBeHome(URL(string: "file:///Users/me/notes.html")))
    }

    @Test func aBlankPageNothingOrAnExtensionsPageCannot() {
        #expect(!Shelves.canBeHome(URL(string: "about:blank")))
        #expect(!Shelves.canBeHome(nil))
        #expect(!Shelves.canBeHome(URL(string: "chrome-extension://abcdefghijklmnop/popup.html")))
    }
}

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

@Suite struct TripTests {
    @Test func aCancelledLoadDoesNotEndTheTrip() {
        #expect(!Shelves.failureEndsTrip(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
    }

    @Test func aHostThatIsNotThereEndsIt() {
        #expect(Shelves.failureEndsTrip(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost))
    }

    @Test func aWebKitFailureEndsIt() {
        #expect(Shelves.failureEndsTrip(domain: "WebKitErrorDomain", code: 102))
    }
}

// Six pins: 1 and 2 in Work (open), 3 loose, 4 and 5 in Play (closed), 6 loose.
private let pinsFixture: [Slot] = [
    slot(1, kept: true, .pins, folder: work.id),
    slot(2, kept: true, .pins, folder: work.id),
    slot(3, kept: true, .pins),
    slot(4, kept: true, .pins, folder: play.id),
    slot(5, kept: true, .pins, folder: play.id),
    slot(6, kept: true, .pins),
]
private let bothFolders = [work, play]
private let side = Folder(id: UUID(uuidString: "F0000000-0000-0000-0000-000000000003")!, name: "Side", open: true)

private func pinID(_ n: Int) -> UUID { slot(n).id }
private func numbers(_ pins: [Slot]) -> [Int] { pins.map { Int($0.id.uuidString.suffix(12))! } }
private func folder(of n: Int, in pins: [Slot]) -> UUID? { pins.first { $0.id == pinID(n) }?.folder }

@Suite struct PinnedRowsTests {
    @Test func foldersShowTheirRowAndOpenOnesTheirPins() {
        let rows = Shelves.pinnedRows(pinsFixture, folders: bothFolders, active: nil)
        #expect(rows == [
            .folder(work.id), .pin(pinID(1), folder: work.id), .pin(pinID(2), folder: work.id),
            .pin(pinID(3), folder: nil), .folder(play.id), .pin(pinID(6), folder: nil),
        ])
    }

    @Test func theTabYouAreOnShowsUnderItsClosedFolder() {
        let rows = Shelves.pinnedRows(pinsFixture, folders: bothFolders, active: pinID(5))
        #expect(rows == [
            .folder(work.id), .pin(pinID(1), folder: work.id), .pin(pinID(2), folder: work.id),
            .pin(pinID(3), folder: nil), .folder(play.id), .pin(pinID(5), folder: play.id), .pin(pinID(6), folder: nil),
        ])
    }

    @Test func aPinInAFolderThatIsNotThereIsDrawnLoose() {
        let ghost = UUID()
        let rows = Shelves.pinnedRows([slot(7, kept: true, .pins, folder: ghost)], folders: [], active: nil)
        #expect(rows == [.pin(pinID(7), folder: nil)])
    }

    @Test func aFolderListedTwiceDoesNotBreakTheDrawing() {
        let twice = Shelves.pinnedRows(pinsFixture, folders: [work, work, play], active: nil)
        let once = Shelves.pinnedRows(pinsFixture, folders: [work, play], active: nil)
        #expect(twice == once)
    }
}

@Suite struct MovePinTests {
    // Rows as drawn: 0 Work, 1 p1, 2 p2, 3 p3, 4 Play (closed), 5 p6.

    @Test func betweenTwoPinsOfAFolderJoinsIt() {
        let out = Shelves.movePin(pinID(3), to: 2, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 3, 2, 4, 5, 6])
        #expect(folder(of: 3, in: out) == work.id)
    }

    @Test func directlyUnderAnOpenFoldersRowJoinsIt() {
        let out = Shelves.movePin(pinID(3), to: 1, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [3, 1, 2, 4, 5, 6])
        #expect(folder(of: 3, in: out) == work.id)
    }

    @Test func belowAFoldersLastPinLeavesIt() {
        let out = Shelves.movePin(pinID(2), to: 3, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 3, 2, 4, 5, 6])
        #expect(folder(of: 2, in: out) == nil)
    }

    @Test func aboveAFoldersRowLeavesIt() {
        let out = Shelves.movePin(pinID(1), to: 0, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 2, 3, 4, 5, 6])
        #expect(folder(of: 1, in: out) == nil)
    }

    @Test func aboveAClosedFolderStaysOut() {
        let out = Shelves.movePin(pinID(6), to: 4, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 2, 3, 6, 4, 5])
        #expect(folder(of: 6, in: out) == nil)
    }

    @Test func pastAClosedFolderGoesAfterItNotIntoIt() {
        let out = Shelves.movePin(pinID(3), to: 4, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 2, 4, 5, 3, 6])
        #expect(folder(of: 3, in: out) == nil)
    }

    @Test func theTabYouAreOnLeavesItsClosedFolder() {
        // Rows: 0 Work, 1 p1, 2 p2, 3 p3, 4 Play, 5 p5 (shown: you are on it), 6 p6.
        let out = Shelves.movePin(pinID(5), to: 4, pins: pinsFixture, folders: bothFolders, active: pinID(5))
        #expect(numbers(out) == [1, 2, 3, 5, 4, 6])
        #expect(folder(of: 5, in: out) == nil)
    }

    @Test func nowhereOrTheSamePlaceChangesNothing() {
        #expect(Shelves.movePin(pinID(3), to: 9, pins: pinsFixture, folders: bothFolders, active: nil) == pinsFixture)
        #expect(Shelves.movePin(pinID(3), to: 3, pins: pinsFixture, folders: bothFolders, active: nil) == pinsFixture)
    }

    @Test func aPinWhoseFolderIsNotKnownTakesTheFolderItsPlaceGives() {
        // Rows: 0 Work, 1 p1, 2 p2, 3 p3, 4 Play, 5 p6, 6 p7 (drawn loose).
        let ghost = UUID()
        let pins = pinsFixture + [slot(7, kept: true, .pins, folder: ghost)]
        let between = Shelves.movePin(pinID(7), to: 2, pins: pins, folders: bothFolders, active: nil)
        #expect(numbers(between) == [1, 7, 2, 3, 4, 5, 6])
        #expect(folder(of: 7, in: between) == work.id)
        let loose = Shelves.movePin(pinID(7), to: 3, pins: pins, folders: bothFolders, active: nil)
        #expect(numbers(loose) == [1, 2, 7, 3, 4, 5, 6])
        #expect(folder(of: 7, in: loose) == nil)
    }
}

@Suite struct MoveFolderTests {
    @Test func aClosedFolderMovedUpTakesItsPins() {
        let out = Shelves.moveFolder(play.id, to: 3, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 2, 4, 5, 3, 6])
    }

    @Test func inTheFirstHalfOfAnotherFolderItLandsBeforeIt() {
        let out = Shelves.moveFolder(play.id, to: 1, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [4, 5, 1, 2, 3, 6])
    }

    @Test func pastTheHalfOfAnotherFolderItLandsAfterIt() {
        let out = Shelves.moveFolder(play.id, to: 2, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [1, 2, 4, 5, 3, 6])
    }

    @Test func anOpenFolderMovedDownPassesOneRow() {
        let out = Shelves.moveFolder(work.id, to: 1, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [3, 1, 2, 4, 5, 6])
    }

    @Test func movedDownPastAClosedFolderItGoesAfterIt() {
        let out = Shelves.moveFolder(work.id, to: 2, pins: pinsFixture, folders: bothFolders, active: nil)
        #expect(numbers(out) == [3, 4, 5, 1, 2, 6])
    }

    @Test func movedDownIntoAnotherFolderItLandsAfterIt() {
        // Rows: 0 Side, 1 p1, 2 p2, 3 Work, 4 p3, 5 p4.
        let pins = [
            slot(1, kept: true, .pins, folder: side.id),
            slot(2, kept: true, .pins),
            slot(3, kept: true, .pins, folder: work.id),
            slot(4, kept: true, .pins, folder: work.id),
        ]
        let out = Shelves.moveFolder(side.id, to: 3, pins: pins, folders: [side, work], active: nil)
        #expect(numbers(out) == [2, 3, 4, 1])
    }

    @Test func carriedDownIntoTheFirstHalfOfAnotherFolderItLandsBeforeIt() {
        let pins = [
            slot(1, kept: true, .pins, folder: side.id),
            slot(2, kept: true, .pins),
            slot(3, kept: true, .pins, folder: work.id),
            slot(4, kept: true, .pins, folder: work.id),
        ]
        let out = Shelves.moveFolder(side.id, to: 2, pins: pins, folders: [side, work], active: nil)
        #expect(numbers(out) == [2, 1, 3, 4])
    }

    @Test func theSameHandTwiceLeavesItWhereItLanded() {
        // Rows: 0 Side, 1 p1, 2 p2, 3 Work, 4 p3, 5 p4, 6 p5.
        let pins = [
            slot(1, kept: true, .pins, folder: side.id),
            slot(2, kept: true, .pins, folder: side.id),
            slot(3, kept: true, .pins, folder: work.id),
            slot(4, kept: true, .pins, folder: work.id),
            slot(5, kept: true, .pins),
        ]
        let folders = [side, work]
        let once = Shelves.moveFolder(side.id, to: 2, pins: pins, folders: folders, active: nil)
        let twice = Shelves.moveFolder(side.id, to: 2, pins: once, folders: folders, active: nil)
        #expect(numbers(once) == [3, 4, 1, 2, 5])
        #expect(numbers(twice) == numbers(once))
    }

    @Test func aClosedFolderHoldingTheTabYouAreOnMovesAsOneBlock() {
        // Rows: 0 Work, 1 p1, 2 p2, 3 p3, 4 Play, 5 p5 (shown: you are on it), 6 p6.
        // Carried to the end, the block is Play's row and p5: were p5 left
        // behind, it would stand on its own before p6.
        let out = Shelves.moveFolder(play.id, to: 6, pins: pinsFixture, folders: bothFolders, active: pinID(5))
        #expect(numbers(out) == [1, 2, 3, 6, 4, 5])
        #expect(folder(of: 4, in: out) == play.id)
        #expect(folder(of: 5, in: out) == play.id)
    }

    @Test func pastTheEndChangesNothing() {
        #expect(Shelves.moveFolder(play.id, to: 6, pins: pinsFixture, folders: bothFolders, active: nil) == pinsFixture)
        #expect(Shelves.moveFolder(play.id, to: 9, pins: pinsFixture, folders: bothFolders, active: nil) == pinsFixture)
    }
}

@Suite struct PlaceTests {
    @Test func intoAFolderGoesToItsEnd() {
        let out = Shelves.place(pinID(3), into: work.id, pins: pinsFixture)
        #expect(numbers(out) == [1, 2, 3, 4, 5, 6])
        #expect(folder(of: 3, in: out) == work.id)
    }

    @Test func intoAClosedFolderGoesToItsEnd() {
        let out = Shelves.place(pinID(6), into: play.id, pins: pinsFixture)
        #expect(numbers(out) == [1, 2, 3, 4, 5, 6])
        #expect(folder(of: 6, in: out) == play.id)
    }

    @Test func outOfAFolderGoesJustAfterIt() {
        let out = Shelves.place(pinID(1), into: nil, pins: pinsFixture)
        #expect(numbers(out) == [2, 1, 3, 4, 5, 6])
        #expect(folder(of: 1, in: out) == nil)
    }

    @Test func theLastPinOutOfAFolderStaysWhereItIs() {
        let pins = [slot(1, kept: true, .pins, folder: work.id), slot(2, kept: true, .pins)]
        let out = Shelves.place(pinID(1), into: nil, pins: pins)
        #expect(numbers(out) == [1, 2])
        #expect(folder(of: 1, in: out) == nil)
    }

    @Test func outOfNoFolderChangesNothing() {
        #expect(Shelves.place(pinID(3), into: nil, pins: pinsFixture) == pinsFixture)
    }
}

@Suite struct FolderBetweenTests {
    // The top bar is one flat row: favorites, pins, then the rest.

    @Test func inTheTopBarBetweenTwoPinsOfAFolderJoinsIt() {
        let row = [slot(1, kept: true), slot(2, kept: true, .pins, folder: work.id), slot(3, kept: true, .pins), slot(4, kept: true, .pins, folder: work.id), slot(5)]
        #expect(Shelves.folderBetween(row, at: 2) == work.id)
    }

    @Test func afterAFoldersLastPinAndBeforeALooseOneIsLoose() {
        let row = [slot(1, kept: true, .pins, folder: work.id), slot(2, kept: true, .pins, folder: work.id), slot(3, kept: true, .pins, folder: work.id), slot(4, kept: true, .pins)]
        #expect(Shelves.folderBetween(row, at: 2) == nil)
    }

    @Test func theFirstPinAfterAFavoriteIsLoose() {
        let row = [slot(1, kept: true), slot(2, kept: true, .pins, folder: work.id), slot(3, kept: true, .pins, folder: work.id)]
        #expect(Shelves.folderBetween(row, at: 1) == nil)
    }

    @Test func betweenTwoFoldersIsLoose() {
        let row = [slot(1, kept: true, .pins, folder: work.id), slot(2, kept: true, .pins, folder: work.id), slot(3, kept: true, .pins, folder: play.id)]
        #expect(Shelves.folderBetween(row, at: 1) == nil)
    }

    @Test func theLastSlotIsLoose() {
        let row = [slot(1, kept: true, .pins, folder: work.id), slot(2, kept: true, .pins, folder: work.id)]
        #expect(Shelves.folderBetween(row, at: 1) == nil)
    }
}

@Suite struct FolderAfterMoveTests {
    // A pin moved in the flat top bar, still carrying the folder it had.

    @Test func theOnlyPinOfAFolderMovedOnePlaceStaysInIt() {
        let row = [slot(2, kept: true, .pins), slot(1, kept: true, .pins, folder: work.id)]
        #expect(Shelves.folderAfterMove(row, at: 1) == work.id)
    }

    @Test func besideAnotherPinOfItsFolderItStays() {
        let row = [slot(2, kept: true, .pins, folder: work.id), slot(1, kept: true, .pins, folder: work.id), slot(3, kept: true, .pins)]
        #expect(Shelves.folderAfterMove(row, at: 1) == work.id)
    }

    @Test func awayFromAFolderThatStillHasPinsItLeaves() {
        let row = [slot(2, kept: true, .pins, folder: work.id), slot(3, kept: true, .pins), slot(1, kept: true, .pins, folder: work.id), slot(4, kept: true, .pins)]
        #expect(Shelves.folderAfterMove(row, at: 2) == nil)
    }

    @Test func awayFromItsFolderAndBetweenTwoPinsOfAnotherItJoinsThatOne() {
        let row = [slot(2, kept: true, .pins, folder: work.id), slot(5, kept: true, .pins, folder: play.id), slot(1, kept: true, .pins, folder: work.id), slot(6, kept: true, .pins, folder: play.id)]
        #expect(Shelves.folderAfterMove(row, at: 2) == play.id)
    }

    @Test func theOnlyPinOfAFolderDroppedInsideAnotherKeepsItsOwn() {
        let row = [slot(5, kept: true, .pins, folder: play.id), slot(1, kept: true, .pins, folder: work.id), slot(6, kept: true, .pins, folder: play.id)]
        #expect(Shelves.folderAfterMove(row, at: 1) == work.id)
    }

    @Test func aLoosePinBetweenTwoPinsOfAFolderJoinsIt() {
        let row = [slot(1, kept: true, .pins, folder: work.id), slot(3, kept: true, .pins), slot(2, kept: true, .pins, folder: work.id)]
        #expect(Shelves.folderAfterMove(row, at: 1) == work.id)
    }

    @Test func aLoosePinBesideALooseOneAndAPinOfAFolderStaysLoose() {
        let row = [slot(3, kept: true, .pins), slot(4, kept: true, .pins), slot(5, kept: true, .pins, folder: play.id)]
        #expect(Shelves.folderAfterMove(row, at: 1) == nil)
    }
}
