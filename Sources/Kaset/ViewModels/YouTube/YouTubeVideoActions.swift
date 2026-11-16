import Foundation
import Observation

// MARK: - YouTubeVideoActions

/// Saves a YouTube video to Watch Later or to a playlist from its context
/// menu, and reports how it went in a toast over the YouTube pages.
///
/// Shared, since video cards sit on pushed pages that don't inherit the
/// YouTube store's environment. `YouTubeContentView` hands it the client.
@MainActor
@Observable
final class YouTubeVideoActions {
    static let shared = YouTubeVideoActions()

    /// A confirmation or failure shown over the YouTube pages.
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    /// The client of the YouTube pages on screen.
    @ObservationIgnored var client: (any YouTubeClientProtocol)?

    /// The latest result; nil once dismissed.
    private(set) var toast: Toast?

    /// How long the playlists may take before the submenu offers a retry.
    private static let playlistLoadTimeout: Duration = .seconds(12)

    private enum PlaylistLoadError: Error {
        case noClient
        case timedOut
    }

    init(client: (any YouTubeClientProtocol)? = nil) {
        self.client = client
    }

    func saveToWatchLater(_ video: YouTubeVideo) async {
        guard let client = self.client else { return }
        do {
            try await client.addToWatchLater(videoId: video.videoId)
            HapticService.toggle()
            self.toast = Toast(message: String(localized: "Added to Watch Later"), isError: false)
        } catch is CancellationError {
            return
        } catch {
            DiagnosticsLogger.api.error("Failed to add a video to Watch Later: \(error.localizedDescription)")
            self.toast = Toast(message: String(localized: "Couldn't add the video to Watch Later."), isError: true)
        }
    }

    /// Adds `video` to `playlist`; true once YouTube accepted it.
    @discardableResult
    func addToPlaylist(_ video: YouTubeVideo, playlist: AddToPlaylistOption) async -> Bool {
        guard let client = self.client else { return false }
        do {
            try await client.addToPlaylist(videoId: video.videoId, playlistId: playlist.playlistId)
            HapticService.toggle()
            self.toast = Toast(message: String(localized: "Added to \(playlist.title)"), isError: false)
            return true
        } catch is CancellationError {
            return false
        } catch {
            DiagnosticsLogger.api.error("Failed to add a video to a playlist: \(error.localizedDescription)")
            self.toast = Toast(message: String(localized: "Couldn't add the video to the playlist."), isError: true)
            return false
        }
    }

    /// The user's playlists for `video`, without Watch Later, which the menu
    /// offers on its own. Gives up after a while so the submenu can retry.
    func playlistOptions(for video: YouTubeVideo) async throws -> [AddToPlaylistOption] {
        guard let client = self.client else { throw PlaylistLoadError.noClient }
        let videoId = video.videoId
        let menu = try await withThrowingTaskGroup(of: AddToPlaylistMenu.self) { group in
            group.addTask {
                try await client.getAddToPlaylistOptions(videoId: videoId)
            }
            group.addTask {
                try await Task.sleep(for: Self.playlistLoadTimeout)
                throw PlaylistLoadError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
        return menu.options.filter { $0.playlistId != "WL" }
    }

    func clearToast(id: UUID) {
        if self.toast?.id == id {
            self.toast = nil
        }
    }
}
