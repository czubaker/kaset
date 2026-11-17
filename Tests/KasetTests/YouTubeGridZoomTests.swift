import Foundation
import Testing
@testable import Kaset

@Suite("YouTubeGridZoom", .tags(.model))
struct YouTubeGridZoomTests {
    @Test("Zoom steps through the levels and stops at either end")
    func stepsThroughLevels() {
        let largest = YouTubeGridZoom.levels.last ?? 0
        let smallest = YouTubeGridZoom.levels.first ?? 0

        #expect(YouTubeGridZoom.zoomedIn(from: 1) == 1.15)
        #expect(YouTubeGridZoom.zoomedOut(from: 1) == 0.9)
        #expect(YouTubeGridZoom.zoomedIn(from: largest) == nil)
        #expect(YouTubeGridZoom.zoomedOut(from: smallest) == nil)
    }

    @Test("A stored value lands on the nearest level")
    func snapsToNearestLevel() {
        let largest = YouTubeGridZoom.levels.last ?? 0
        let smallest = YouTubeGridZoom.levels.first ?? 0

        #expect(YouTubeGridZoom.level(nearest: 1.12) == 1.15)
        #expect(YouTubeGridZoom.level(nearest: 5) == largest)
        #expect(YouTubeGridZoom.level(nearest: -1) == smallest)
        #expect(YouTubeGridZoom.level(nearest: YouTubeGridZoom.standard) == 1)
    }

    @Test("Zoom applies to card grids, not the watch page, Search, or Shorts")
    func appliesToGridPages() {
        let video = MockYouTubeClient.makeVideo()
        #expect(YouTubeGridZoom.isGridPage(.channel(channelId: "UCtest")))
        #expect(YouTubeGridZoom.isGridPage(.playlist(playlistId: "PLtest")))
        #expect(!YouTubeGridZoom.isGridPage(.watch(video)))
        #expect(YouTubeGridZoom.isGridPage(YouTubeNavigationItem.subscriptions))
        #expect(YouTubeGridZoom.isGridPage(YouTubeNavigationItem.playlist(id: "PLtest")))
        #expect(!YouTubeGridZoom.isGridPage(YouTubeNavigationItem.search))
        #expect(!YouTubeGridZoom.isGridPage(YouTubeNavigationItem.shorts))
    }

    @Test("Thumbnails decode at two sizes, so zoom steps reuse them")
    func layoutScales() {
        let standard = CGSize(width: 320, height: 180)
        let large = CGSize(width: 640, height: 360)
        #expect(YouTubeGridZoom.thumbnailSize(zoom: 0.7) == standard)
        #expect(YouTubeGridZoom.thumbnailSize(zoom: 1) == standard)
        #expect(YouTubeGridZoom.thumbnailSize(zoom: 1.15) == large)
        #expect(YouTubeGridZoom.thumbnailSize(zoom: 2) == large)
        #expect(YouTubeGridZoom.railCardWidth(zoom: 1) == 284)
    }
}
