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
