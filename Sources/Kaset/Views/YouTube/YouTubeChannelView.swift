import SwiftUI

// MARK: - YouTubeChannelView

/// A YouTube channel page: header plus the landing-tab video grid.
struct YouTubeChannelView: View {
    @State private var viewModel: YouTubeChannelViewModel

    @State private var gridSettings = SettingsManager.shared

    /// View → Zoom In / Zoom Out scale the cards (YouTubeGridZoom).
    private var columns: [GridItem] {
        YouTubeGridZoom.columns(zoom: self.gridSettings.youtubeGridZoom)
    }

    init(channelId: String, client: any YouTubeClientProtocol) {
        self._viewModel = State(
            initialValue: YouTubeChannelViewModel(channelId: channelId, client: client)
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
        .navigationTitle(Text(self.viewModel.detail?.channel.name ?? ""))
        .task {
            await self.viewModel.load()
        }
        .youtubePageRefreshable {
            await self.viewModel.refresh()
        }
    }

    private func content(for detail: YouTubeChannelDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                self.header(for: detail.channel)

                if detail.tabs.count > 1 {
                    self.tabPicker(detail.tabs)
                }

                if let tab = self.viewModel.selectedTab, tab.kind != .home {
                    self.tabContent(for: tab)
                } else {
                    self.videoGrid(detail.videos, continuation: nil)
                }
            }
            .padding(.vertical, 20)
            // Edge-to-edge with a resting inset so content extends under the
            // floating glass sidebar.
            .detailScrollContentInset()
        }
    }

    /// Home, Videos, Shorts, Live, Playlists, as the channel names them.
    private func tabPicker(_ tabs: [YouTubeChannelTab]) -> some View {
        Picker(String(localized: "Channel Section"), selection: Binding(
            get: { self.viewModel.selectedTab ?? tabs.first },
            set: { tab in
                guard let tab else { return }
                Task { await self.viewModel.select(tab) }
            }
        )) {
            ForEach(tabs) { tab in
                Text(tab.title).tag(Optional(tab))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private func tabContent(for tab: YouTubeChannelTab) -> some View {
        if let page = self.viewModel.page(for: tab) {
            VStack(alignment: .leading, spacing: 16) {
                if !page.sortOptions.isEmpty {
                    self.sortPicker(page.sortOptions)
                }

                if self.viewModel.loadingTabs.contains(tab.params) {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    switch tab.kind {
                    case .shorts:
                        self.shortsGrid(page.shorts, continuation: page.continuation)
                    case .playlists:
                        self.playlistGrid(page.playlists, continuation: page.continuation)
                    case .home, .videos, .live:
                        self.videoGrid(page.videos, continuation: page.continuation)
                    }
                }
            }
        } else if let error = self.viewModel.tabErrors[tab.params] {
            ErrorView(title: error.title, message: error.message, isRetryable: error.isRetryable) {
                Task { await self.viewModel.select(tab) }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    /// Latest, Popular, Oldest.
    private func sortPicker(_ options: [YouTubeChannelSortOption]) -> some View {
        Picker(String(localized: "Sort Order"), selection: Binding(
            get: { options.first(where: \.isSelected)?.title ?? options.first?.title ?? "" },
            set: { title in
                guard let option = options.first(where: { $0.title == title }) else { return }
                Task { await self.viewModel.selectSort(option) }
            }
        )) {
            ForEach(options) { option in
                Text(option.title).tag(option.title)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private func videoGrid(_ videos: [YouTubeVideo], continuation: String?) -> some View {
        if videos.isEmpty, continuation == nil {
            ContentUnavailableView {
                Label(String(localized: "No videos"), systemImage: "play.rectangle")
            }
        } else {
            LazyVGrid(columns: self.columns, spacing: 20) {
                ForEach(videos) { video in
                    NavigationLink(value: YouTubeRoute.watch(video)) {
                        VideoCard(video: video, thumbnailSize: YouTubeGridZoom.thumbnailSize(zoom: self.gridSettings.youtubeGridZoom))
                    }
                    .buttonStyle(.interactiveCard)
                    .youtubeVideoContextMenu(for: video)
                }
                self.nextPageSentinel(continuation: continuation)
            }
        }
    }

    @ViewBuilder
    private func shortsGrid(_ shorts: [YouTubeVideo], continuation: String?) -> some View {
        if shorts.isEmpty, continuation == nil {
            ContentUnavailableView {
                Label(String(localized: "No videos"), systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
            }
        } else {
            let zoom = self.gridSettings.youtubeGridZoom
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150 * zoom, maximum: 220 * zoom), spacing: 14)], spacing: 20) {
                ForEach(shorts) { short in
                    NavigationLink(value: YouTubeRoute.watch(short)) {
                        YouTubeShortCard(video: short)
                    }
                    .buttonStyle(.interactiveCard)
                    .youtubeVideoContextMenu(for: short)
                }
                self.nextPageSentinel(continuation: continuation)
            }
        }
    }

    @ViewBuilder
    private func playlistGrid(_ playlists: [YouTubePlaylist], continuation: String?) -> some View {
        if playlists.isEmpty, continuation == nil {
            ContentUnavailableView {
                Label(String(localized: "No Playlists"), systemImage: "list.and.film")
            }
        } else {
            LazyVGrid(columns: self.columns, spacing: 20) {
                ForEach(playlists) { playlist in
                    NavigationLink(value: YouTubeRoute.playlist(playlistId: playlist.playlistId)) {
                        YouTubePlaylistCard(playlist: playlist)
                    }
                    .buttonStyle(.interactiveCard)
                }
                self.nextPageSentinel(continuation: continuation)
            }
        }
    }

    /// Loads the next page as the end of the grid scrolls into view, once
    /// per page token; a failed page waits for Try Again.
    @ViewBuilder
    private func nextPageSentinel(continuation: String?) -> some View {
        if let continuation {
            if self.viewModel.hasLoadMoreFailed {
                Button(String(localized: "Try Again")) {
                    Task { await self.viewModel.retryLoadMore() }
                }
                .buttonStyle(.bordered)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .task(id: continuation) {
                        await self.viewModel.loadMore()
                    }
            }
        }
    }

    private func header(for channel: YouTubeChannel) -> some View {
        HStack(spacing: 16) {
            CachedAsyncImage(
                url: channel.thumbnailURL,
                targetSize: CGSize(width: 80, height: 80)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                    }
            }
            .frame(width: 80, height: 80)
            .clipShape(.circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.title.bold())
                    .lineLimit(1)

                let meta = [channel.handle, channel.subscriberCountText].compactMap(\.self)
                if !meta.isEmpty {
                    Text(meta.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let description = channel.descriptionSnippet, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - YouTubeShortCard

/// A Short in a channel's Shorts grid: its vertical thumbnail, title, and views.
struct YouTubeShortCard: View {
    let video: YouTubeVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(
                url: self.video.thumbnailURL,
                targetSize: CGSize(width: 270, height: 480)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 10))

            Text(self.video.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let views = self.video.viewCountText {
                Text(views)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
