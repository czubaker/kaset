import Foundation
import Observation

/// View model for a YouTube playlist page.
@MainActor
@Observable
final class YouTubePlaylistViewModel {
    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Loaded playlist detail.
    private(set) var detail: YouTubePlaylistDetail?

    let playlistId: String
    /// Invalidates stale in-flight loads when a newer one starts
    /// (SwiftUI restarts .task during launch/layout churn; latest wins).
    private var loadGeneration = 0

    let client: any YouTubeClientProtocol
    private let logger = DiagnosticsLogger.api

    init(playlistId: String, client: any YouTubeClientProtocol) {
        self.playlistId = playlistId
        self.client = client
    }

    func load() async {
        self.loadGeneration += 1
        let generation = self.loadGeneration
        self.loadingState = .loading
        do {
            let detail = try await self.client.getPlaylist(playlistId: self.playlistId)
            guard generation == self.loadGeneration else { return }
            self.detail = detail
            self.loadingState = .loaded
        } catch {
            guard generation == self.loadGeneration else { return }
            // A cancelled load (view went away mid-flight) is not an
            // error; reset so the next task run reloads.
            if error is CancellationError {
                self.loadingState = .idle
                return
            }
            self.logger.error("Failed to load YouTube playlist: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Drops a video another menu took off this playlist.
    func dropVideo(id videoId: String) {
        guard let detail = self.detail, detail.videos.contains(where: { $0.videoId == videoId }) else { return }
        self.detail = YouTubePlaylistDetail(
            playlist: detail.playlist,
            videos: detail.videos.filter { $0.videoId != videoId }
        )
    }

    /// Takes `video` (every copy of it) off the page at once and puts it back
    /// where it was if `remove` fails, unless the page reloaded meanwhile.
    /// Only that video comes back: other removals made since stay applied.
    func removeVideo(_ video: YouTubeVideo, using remove: (YouTubeVideo) async -> Bool) async {
        guard let detail = self.detail else { return }
        let generation = self.loadGeneration
        let copies = detail.videos.enumerated().filter { $0.element.videoId == video.videoId }
        self.detail = YouTubePlaylistDetail(
            playlist: detail.playlist,
            videos: detail.videos.filter { $0.videoId != video.videoId }
        )
        let removed = await remove(video)
        guard !removed, generation == self.loadGeneration, let current = self.detail,
              !current.videos.contains(where: { $0.videoId == video.videoId })
        else { return }
        var videos = current.videos
        for (index, copy) in copies {
            videos.insert(copy, at: min(index, videos.count))
        }
        self.detail = YouTubePlaylistDetail(playlist: current.playlist, videos: videos)
    }
}
