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

    /// Bumped by every playlist edit and account change, so a menu that keeps
    /// one video's checkmarks (the player bar's) reloads them.
    private(set) var membershipGeneration = 0

    /// A video taken off a playlist, so that playlist's page can drop its card
    /// whichever menu removed it.
    struct PlaylistRemoval: Equatable {
        let id = UUID()
        let videoId: String
        let playlistId: String
    }

    private(set) var lastPlaylistRemoval: PlaylistRemoval?

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
            self.membershipGeneration += 1
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
            self.membershipGeneration += 1
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

    /// Removes `video` from a playlist; true once YouTube accepted it.
    @discardableResult
    func removeFromPlaylist(_ video: YouTubeVideo, playlistId: String, title: String) async -> Bool {
        guard let client = self.client else { return false }
        do {
            try await client.removeFromPlaylist(videoId: video.videoId, playlistId: playlistId)
            self.membershipGeneration += 1
            self.lastPlaylistRemoval = PlaylistRemoval(videoId: video.videoId, playlistId: playlistId)
            HapticService.toggle()
            self.toast = Toast(message: String(localized: "Removed from \(title)"), isError: false)
            return true
        } catch is CancellationError {
            return false
        } catch {
            DiagnosticsLogger.api.error("Failed to remove a video from a playlist: \(error.localizedDescription)")
            self.toast = Toast(message: String(localized: "Couldn't remove the video from the playlist."), isError: true)
            return false
        }
    }

    /// Whether the user can take videos off `playlistId`: Watch Later, or a
    /// playlist the Save dialog offers for one of its videos (their own and
    /// collaborative ones; not playlists saved from others, nor Liked Videos).
    func canEditPlaylist(_ playlistId: String, sampleVideo: YouTubeVideo) async -> Bool {
        if playlistId == "WL" {
            return true
        }
        guard playlistId != "LL" else { return false }
        let options = try? await self.playlistOptions(for: sampleVideo)
        return options?.contains { $0.playlistId == playlistId } ?? false
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

    /// Makes menus reload their checkmarks, after the account changes.
    func invalidateMembership() {
        self.membershipGeneration += 1
    }

    func clearToast(id: UUID) {
        if self.toast?.id == id {
            self.toast = nil
        }
    }
}

// MARK: - YouTubePlaylistMembership

/// Which of the user's playlists hold one video, for a menu that adds the
/// video to a playlist or, for a checked one, removes it. Shared by the video
/// context menu and the player bar's Save to Playlist button.
@MainActor
@Observable
final class YouTubePlaylistMembership {
    /// The latest list for `videoId`; kept while a newer one loads, since an
    /// open menu doesn't redraw.
    private(set) var options: [AddToPlaylistOption]?
    private(set) var didFail = false
    private(set) var videoId: String?
    /// Only the latest load's result is kept, so a load for a new video is
    /// never dropped behind one still running for the previous video.
    private var latestLoad = 0

    private let actions: YouTubeVideoActions

    init(actions: YouTubeVideoActions = .shared) {
        self.actions = actions
    }

    func load(for video: YouTubeVideo) async {
        if video.videoId != self.videoId {
            // Another video's checkmarks would be wrong.
            self.options = nil
            self.didFail = false
            self.videoId = video.videoId
        }
        self.latestLoad += 1
        let load = self.latestLoad
        do {
            let options = try await self.actions.playlistOptions(for: video)
            guard load == self.latestLoad else { return }
            self.options = options
            self.didFail = false
        } catch is CancellationError {
            // Closing the menu cancels the load; the next open tries again.
        } catch {
            guard load == self.latestLoad else { return }
            DiagnosticsLogger.ui.error("Failed to load YouTube playlists: \(error.localizedDescription)")
            // A list from an earlier load stays usable.
            self.didFail = self.options == nil
        }
    }

    /// Adds the video to an unchecked playlist or removes it from a checked
    /// one, then flips the checkmark so the next open shows the change.
    func toggle(_ option: AddToPlaylistOption, for video: YouTubeVideo) async {
        let succeeded = if option.isSelected {
            await self.actions.removeFromPlaylist(video, playlistId: option.playlistId, title: option.title)
        } else {
            await self.actions.addToPlaylist(video, playlist: option)
        }
        guard succeeded, self.videoId == video.videoId else { return }
        self.options = self.options?.map { $0.playlistId == option.playlistId ? $0.withSelection(!option.isSelected) : $0 }
    }
}

extension AddToPlaylistOption {
    /// The same playlist, marked as holding the video or not.
    func withSelection(_ isSelected: Bool) -> Self {
        Self(
            playlistId: self.playlistId,
            title: self.title,
            subtitle: self.subtitle,
            thumbnailURL: self.thumbnailURL,
            isSelected: isSelected,
            privacyStatus: self.privacyStatus
        )
    }
}
