import Foundation
import Testing
@testable import Search

@Suite struct SessionTests {
    /// A session.json as every version before shelves wrote it.
    let old = """
    {"tabs":[
      {"url":"https://mail.example.com/","title":"Mail","pin":"M"},
      {"url":"https://news.example.com/a","title":"A story"},
      {"url":"https://cal.example.com/week","title":"Calendar","pin":"C","name":"Cal"}
    ],"active":1}
    """

    @Test func anOldFileReadsWithItsPinsAsFavoritesAtHome() throws {
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(old.utf8))
        #expect(shape.tabs.count == 3)
        #expect(shape.folders == nil)
        #expect(shape.tabs[0].keptShelf == .favorites)
        #expect(shape.tabs[0].keptHome == URL(string: "https://mail.example.com/"))
        #expect(shape.tabs[2].keptHome == URL(string: "https://cal.example.com/week"))
        #expect(shape.tabs[2].name == "Cal")
    }

    @Test func aTabNotKeptHasNoHomeAndNoFolder() throws {
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(old.utf8))
        #expect(shape.tabs[1].keptHome == nil)
        #expect(shape.tabs[1].folderID == nil)
    }

    @Test func anUnknownShelfIsAFavorite() {
        let entry = Session.Entry(url: "https://a.com", title: "", pin: "A", shelf: "shelves")
        #expect(entry.keptShelf == .favorites)
    }

    /// `URL(string:)` takes almost anything; an empty string is one thing it
    /// reliably won't.
    @Test func aHomeThatWontParseFallsBackToTheURL() {
        let entry = Session.Entry(url: "https://a.com/x", title: "", pin: "A", home: "")
        #expect(entry.keptHome == URL(string: "https://a.com/x"))
    }

    @Test func aNewFileSurvivesTheRoundTrip() throws {
        let folder = Folder(id: UUID(), name: "Work", open: false)
        let shape = Session.Shape(
            tabs: [
                .init(url: "https://a.com/x", title: "A", pin: "A", shelf: "pins",
                      home: "https://a.com/", folder: folder.id.uuidString),
                .init(url: "https://b.com", title: "B"),
            ],
            active: 0,
            folders: [folder]
        )
        let back = try JSONDecoder().decode(Session.Shape.self, from: JSONEncoder().encode(shape))
        #expect(back.tabs[0].keptShelf == .pins)
        #expect(back.tabs[0].keptHome == URL(string: "https://a.com/"))
        #expect(back.tabs[0].folderID == folder.id)
        #expect(back.folders == [folder])
        #expect(back.tabs[1].keptHome == nil)
    }

    @Test func aFolderThatWontReadIsDroppedNotTheSession() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A","pin":"A","shelf":"pins","folder":"F0000000-0000-0000-0000-000000000001"}],
         "active":0,
         "folders":[{"id":"F0000000-0000-0000-0000-000000000001","name":"Work","open":true},{"name":"no id"}]}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.tabs.count == 1)
        #expect(shape.folders?.map(\.name) == ["Work"])
    }

    @Test func aFolderListedTwiceStillReads() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A","pin":"A","shelf":"pins","folder":"F0000000-0000-0000-0000-000000000001"}],
         "active":0,
         "folders":[{"id":"F0000000-0000-0000-0000-000000000001","name":"Work","open":true},{"id":"F0000000-0000-0000-0000-000000000001","name":"Work again","open":false}]}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.folders?.count == 2)
        let slots = shape.tabs.map { Slot(id: UUID(), kept: $0.pin != nil, shelf: $0.keptShelf, folder: $0.folderID) }
        let (_, folders) = Shelves.tidy(slots, folders: shape.folders ?? [])
        #expect(folders.map(\.name) == ["Work"])
    }

    @Test func foldersThatAreNotAListAreDroppedNotTheSession() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A"}],"active":0,"folders":"nonsense"}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.tabs.count == 1)
        #expect(shape.folders == nil)
    }

    @Test func splitsAreReadBack() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A"},{"url":"https://b.com/","title":"B"}],"active":0,
         "splits":[{"tabs":[0,1],"widths":[0.4,0.6]}]}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.splits == [SavedSplit(tabs: [0, 1], widths: [0.4, 0.6])])
    }

    @Test func aSplitThatWontReadIsDroppedNotTheSession() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A"}],"active":0,
         "splits":[{"tabs":[0,1],"widths":[0.5,0.5]},{"tabs":"nonsense"}]}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.tabs.count == 1)
        #expect(shape.splits?.count == 1)
    }
}
