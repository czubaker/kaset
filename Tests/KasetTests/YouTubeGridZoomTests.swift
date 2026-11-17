import Testing
@testable import Kaset

@Suite("YouTubeHomeZoom", .tags(.model))
struct YouTubeHomeZoomTests {
    @Test("Zoom steps through the levels and stops at either end")
    func stepsThroughLevels() {
        let largest = YouTubeHomeZoom.levels.last ?? 0
        let smallest = YouTubeHomeZoom.levels.first ?? 0

        #expect(YouTubeHomeZoom.zoomedIn(from: 1) == 1.15)
        #expect(YouTubeHomeZoom.zoomedOut(from: 1) == 0.9)
        #expect(YouTubeHomeZoom.zoomedIn(from: largest) == nil)
        #expect(YouTubeHomeZoom.zoomedOut(from: smallest) == nil)
    }

    @Test("A stored value lands on the nearest level")
    func snapsToNearestLevel() {
        let largest = YouTubeHomeZoom.levels.last ?? 0
        let smallest = YouTubeHomeZoom.levels.first ?? 0

        #expect(YouTubeHomeZoom.level(nearest: 1.12) == 1.15)
        #expect(YouTubeHomeZoom.level(nearest: 5) == largest)
        #expect(YouTubeHomeZoom.level(nearest: -1) == smallest)
        #expect(YouTubeHomeZoom.level(nearest: YouTubeHomeZoom.standard) == 1)
    }
}
