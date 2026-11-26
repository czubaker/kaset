import SwiftUI

/// A YouTube playlist page: header plus its video rows.
struct YouTubePlaylistDetailView: View {
    @State private var viewModel: YouTubePlaylistViewModel
    @Environment(AuthService.self) private var authService

    @State private var gridSettings = SettingsManager.shared
    /// Whether the user can take videos off this playlist (known once a
    /// video has loaded to ask the Save dialog with).
    @State private var canRemoveVideos = false

    /// View → Zoom In / Zoom Out scale the cards (YouTubeGridZoom).
    private var columns: [GridItem] {
        YouTubeGridZoom.columns(zoom: self.gridSettings.youtubeGridZoom)
    }

    init(playlistId: String, client: any YouTubeClientProtocol) {
        self._viewModel = State(
            initialValue: YouTubePlaylistViewModel(playlistId: playlistId, client: client)
        )
    }

    var body: some View {
        Group {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                LoadingView()
            case let .error(error):
                ErrorView(
                    title: error.title,
                    message: error.message,
                    isRetryable: error.isRetryable
                ) {
                    Task {
                        await self.viewModel.load()
                    }
                }
            case .loaded, .loadingMore:
                if let detail = self.viewModel.detail {
                    self.content(for: detail)
                }
            }
        }
        .navigationTitle(Text(self.viewModel.detail?.playlist.title ?? ""))
        .task {
            await self.viewModel.load()
        }
        .task(id: self.viewModel.detail?.videos.first?.videoId) {
            // The Save dialog needs an account; signed out, nothing is editable.
            guard self.authService.hasPersonalAccount, let sample = self.viewModel.detail?.videos.first else {
                self.canRemoveVideos = false
                return
            }
            self.canRemoveVideos = await YouTubeVideoActions.shared.canEditPlaylist(
                self.viewModel.playlistId,
                sampleVideo: sample
            )
        }
        .youtubePageRefreshable {
            await self.viewModel.load()
        }
        // Unchecking this playlist in a card's Add to Playlist takes the
        // video off it too.
        .onChange(of: YouTubeVideoActions.shared.lastPlaylistRemoval) { _, removal in
            guard let removal, removal.playlistId == self.viewModel.playlistId else { return }
            self.viewModel.dropVideo(id: removal.videoId)
        }
    }

    /// Remove from Watch Later / Remove from Playlist, on playlists the user
    /// can edit.
    private func removal(of video: YouTubeVideo, from detail: YouTubePlaylistDetail) -> YouTubeVideoRemoval? {
        guard self.canRemoveVideos else { return nil }
        let isWatchLater = self.viewModel.playlistId == "WL"
        let playlistTitle = isWatchLater ? String(localized: "Watch Later") : detail.playlist.title
        return YouTubeVideoRemoval(
            title: isWatchLater ? String(localized: "Remove from Watch Later") : String(localized: "Remove from Playlist")
        ) {
            Task {
                await self.viewModel.removeVideo(video) { video in
                    await YouTubeVideoActions.shared.removeFromPlaylist(
                        video,
                        playlistId: self.viewModel.playlistId,
                        title: playlistTitle
                    )
                }
            }
        }
    }

    private func content(for detail: YouTubePlaylistDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.playlist.title)
                        .font(.title.bold())
                        .lineLimit(2)

                    let meta = [detail.playlist.channelName, detail.playlist.videoCountText]
                        .compactMap(\.self)
                    if !meta.isEmpty {
                        Text(meta.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if self.authService.hasPersonalAccount, let isSaved = detail.isSavedToLibrary {
                        Button {
                            Task { await self.viewModel.toggleSaved() }
                        } label: {
                            Label(
                                isSaved ? String(localized: "Saved") : String(localized: "Save to Library"),
                                systemImage: isSaved ? "checkmark" : "plus"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(self.viewModel.isSaveInFlight)
                        .padding(.top, 6)
                    }
                }

                if detail.videos.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No videos"), systemImage: "list.and.film")
                    }
                } else {
                    LazyVGrid(columns: self.columns, spacing: 20) {
                        ForEach(detail.videos) { video in
                            NavigationLink(value: YouTubeRoute.watch(video)) {
                                VideoCard(video: video, thumbnailSize: YouTubeGridZoom.thumbnailSize(zoom: self.gridSettings.youtubeGridZoom))
                            }
                            .buttonStyle(.interactiveCard)
                            .youtubeVideoContextMenu(for: video, removal: self.removal(of: video, from: detail))
                        }
                    }
                }
            }
            .padding(.vertical, 20)
            // Edge-to-edge with a resting inset so content extends under the
            // floating glass sidebar.
            .detailScrollContentInset()
        }
    }
}
