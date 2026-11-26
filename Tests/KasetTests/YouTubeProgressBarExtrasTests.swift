import Foundation
import SwiftUI
import Testing
@testable import Kaset

// MARK: - YouTubeProgressBarExtrasTests

/// The "most replayed" heatmap, from the watch-next response to the curve.
/// Shapes follow a response captured with api-explorer (November 2026);
/// IDs are placeholders.
@Suite(.tags(.parser))
struct YouTubeProgressBarExtrasTests {
    private static func response(videoId: String, markers: [[String: Any]], entityVideoId: String) -> [String: Any] {
        [
            "currentVideoEndpoint": ["watchEndpoint": ["videoId": videoId]],
            "frameworkUpdates": ["entityBatchUpdate": ["mutations": [
                ["payload": ["macroMarkersListEntity": [
                    "externalVideoId": entityVideoId,
                    "markersList": ["markerType": "MARKER_TYPE_HEATMAP", "markers": markers],
                ]]],
            ]]],
        ]
    }

    private static var markers: [[String: Any]] {
        [
            ["startMillis": "0", "durationMillis": "2000", "intensityScoreNormalized": 1],
            ["startMillis": "2000", "durationMillis": "2000", "intensityScoreNormalized": 0.25],
            ["startMillis": "4000", "durationMillis": "2000", "intensityScoreNormalized": 0.5],
        ]
    }

    @Test("Heatmap samples sit mid-slice along the video with their intensity")
    func parsesHeatmap() {
        let heatmap = WatchNextParser.heatmap(of: Self.response(videoId: "v1", markers: Self.markers, entityVideoId: "v1"))
        #expect(heatmap.count == 3)
        #expect(abs(heatmap[0].fraction - 1.0 / 6) < 0.0001)
        #expect(abs(heatmap[2].fraction - 5.0 / 6) < 0.0001)
        #expect(heatmap.map(\.intensity) == [1, 0.25, 0.5])
    }

    @Test("Another video's heatmap, or a response without one, gives none")
    func ignoresOtherVideos() {
        #expect(WatchNextParser.heatmap(of: Self.response(videoId: "v1", markers: Self.markers, entityVideoId: "v2")).isEmpty)
        #expect(WatchNextParser.heatmap(of: ["contents": [:]]).isEmpty)
    }

    @Test("The curve needs two samples, and closed it encloses an area")
    func drawsTheCurve() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 20)
        let one = [YouTubeHeatmapMarker(fraction: 0.5, intensity: 1)]
        #expect(PlayerBarHeatmapShape(samples: one).path(in: rect).isEmpty)
        let samples = WatchNextParser.heatmap(of: Self.response(videoId: "v1", markers: Self.markers, entityVideoId: "v1"))
        let path = PlayerBarHeatmapShape(samples: samples).path(in: rect)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.minY < 1) // the intensity-1 peak reaches the top
        #expect(path.boundingRect.maxX == 100)
    }
}
