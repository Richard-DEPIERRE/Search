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
}
