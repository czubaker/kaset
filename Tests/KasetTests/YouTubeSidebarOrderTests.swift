import Foundation
import Testing
@testable import Kaset

@Suite("YouTubeSidebarOrder", .tags(.model))
struct YouTubeSidebarOrderTests {
    @Test("The standard order is the sidebar as it was, with Playlists last")
    func standardOrder() {
        let order = YouTubeSidebarOrder.standard
        let expectedCollection: [YouTubeNavigationItem] = [.likedVideos, .watchLater, .history, .playlists]
        #expect(order.items(in: .collection) == expectedCollection)
        #expect(order.items(in: .main) == YouTubeSidebarSection.main.standardItems)
    }

    @Test("Moving puts an item before another, or at the end without one")
    func movesWithinSection() {
        var order = YouTubeSidebarOrder.standard
        let historyFirst: [YouTubeNavigationItem] = [.history, .likedVideos, .watchLater, .playlists]
        let likedLast: [YouTubeNavigationItem] = [.history, .watchLater, .playlists, .likedVideos]

        let movedHistory = order.move(.history, before: .likedVideos, in: .collection)
        #expect(movedHistory)
        #expect(order.items(in: .collection) == historyFirst)
        let movedLiked = order.move(.likedVideos, before: nil, in: .collection)
        #expect(movedLiked)
        #expect(order.items(in: .collection) == likedLast)
    }

    @Test("Items don't move across sections")
    func refusesOtherSections() {
        var order = YouTubeSidebarOrder.standard
        let movedHome = order.move(.home, before: .likedVideos, in: .collection)
        let movedBeforeHome = order.move(.history, before: .home, in: .collection)
        #expect(!movedHome)
        #expect(!movedBeforeHome)
        #expect(order == .standard)
    }

    @Test("A saved order keeps known items, drops unknown ones, and appends new ones")
    func decodesLeniently() throws {
        let json = Data(#"{"orders": {"collection": ["Playlists", "History", "bogus"]}}"#.utf8)
        let order = try JSONDecoder().decode(YouTubeSidebarOrder.self, from: json)
        let expected: [YouTubeNavigationItem] = [.playlists, .history, .likedVideos, .watchLater]
        #expect(order.items(in: .collection) == expected)
    }
}
