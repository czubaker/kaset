import Foundation
import Observation

/// View model for a YouTube channel page: its header and Home videos, then
/// each tab the user opens (Videos, Shorts, Live, Playlists), page by page and
/// in the sort they pick.
@MainActor
@Observable
final class YouTubeChannelViewModel {
    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Loaded channel detail.
    private(set) var detail: YouTubeChannelDetail?

    /// The tab on screen; Home until another is picked.
    private(set) var selectedTab: YouTubeChannelTab?

    /// Each opened tab's loaded items, by the tab's params. Kept while the
    /// user switches tabs, so going back doesn't load again.
    private(set) var tabPages: [String: YouTubeChannelTabPage] = [:]

    /// Tabs with a first page or a sort loading.
    private(set) var loadingTabs: Set<String> = []

    /// Tabs whose first page failed.
    private(set) var tabErrors: [String: LoadingError] = [:]

    let channelId: String
    /// Invalidates stale in-flight loads when a newer one starts
    /// (SwiftUI restarts .task during launch/layout churn; latest wins).
    private var loadGeneration = 0
    /// Per tab: bumped by a reload or a sort, so older pages are dropped.
    private var tabGenerations: [String: Int] = [:]
    /// Tabs with a next page loading, so the sentinel asks once.
    private var loadingMoreTabs: Set<String> = []

    let client: any YouTubeClientProtocol
    private let logger = DiagnosticsLogger.api

    init(channelId: String, client: any YouTubeClientProtocol) {
        self.channelId = channelId
        self.client = client
    }

    func load() async {
        self.loadGeneration += 1
        let generation = self.loadGeneration
        self.loadingState = .loading
        do {
            let detail = try await self.client.getChannel(channelId: self.channelId)
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
            self.logger.error("Failed to load YouTube channel: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Reloads the header and Home, and the tab on screen from its first page.
    func refresh() async {
        self.tabPages = [:]
        self.tabErrors = [:]
        await self.load()
        if let tab = self.selectedTab, tab.kind != .home {
            await self.loadTab(tab)
        }
    }

    // MARK: Tabs

    /// Shows `tab`, loading its first page the first time.
    func select(_ tab: YouTubeChannelTab) async {
        self.selectedTab = tab
        guard tab.kind != .home, self.tabPages[tab.params] == nil, !self.loadingTabs.contains(tab.params) else {
            return
        }
        await self.loadTab(tab)
    }

    func page(for tab: YouTubeChannelTab) -> YouTubeChannelTabPage? {
        self.tabPages[tab.params]
    }

    /// Loads the next page of the tab on screen, once per token.
    func loadMore() async {
        guard let tab = self.selectedTab,
              let token = self.tabPages[tab.params]?.continuation,
              !self.loadingMoreTabs.contains(tab.params)
        else { return }
        let key = tab.params
        let generation = self.tabGenerations[key, default: 0]
        self.loadingMoreTabs.insert(key)
        defer { self.loadingMoreTabs.remove(key) }
        do {
            let next = try await self.client.getChannelTabContinuation(token)
            guard generation == self.tabGenerations[key, default: 0], var page = self.tabPages[key] else { return }
            page.videos = YouTubeFeedParser.deduplicate(page.videos + next.videos)
            page.shorts = YouTubeFeedParser.deduplicate(page.shorts + next.shorts)
            var seen = Set(page.playlists.map(\.playlistId))
            page.playlists += next.playlists.filter { seen.insert($0.playlistId).inserted }
            page.continuation = next.continuation
            self.tabPages[key] = page
        } catch {
            guard !(error is CancellationError) else { return }
            self.logger.error("Failed to load more of a YouTube channel tab: \(error.localizedDescription)")
        }
    }

    /// Reloads the tab on screen in another sort (Latest, Popular, Oldest).
    func selectSort(_ option: YouTubeChannelSortOption) async {
        guard let tab = self.selectedTab, let token = option.continuation, !option.isSelected else { return }
        let key = tab.params
        let generation = self.bumpGeneration(for: key)
        self.loadingTabs.insert(key)
        defer {
            if generation == self.tabGenerations[key, default: 0] {
                self.loadingTabs.remove(key)
            }
        }
        do {
            var page = try await self.client.getChannelTabContinuation(token)
            guard generation == self.tabGenerations[key, default: 0] else { return }
            // The reload brings the sort chips with the new selection; keep
            // the old ones, marked, if it didn't.
            if page.sortOptions.isEmpty {
                page.sortOptions = (self.tabPages[key]?.sortOptions ?? []).map {
                    YouTubeChannelSortOption(title: $0.title, continuation: $0.continuation, isSelected: $0.title == option.title)
                }
            }
            self.tabPages[key] = page
        } catch {
            guard !(error is CancellationError) else { return }
            self.logger.error("Failed to sort a YouTube channel tab: \(error.localizedDescription)")
        }
    }

    private func loadTab(_ tab: YouTubeChannelTab) async {
        let key = tab.params
        let generation = self.bumpGeneration(for: key)
        self.loadingTabs.insert(key)
        self.tabErrors[key] = nil
        defer {
            if generation == self.tabGenerations[key, default: 0] {
                self.loadingTabs.remove(key)
            }
        }
        do {
            let page = try await self.client.getChannelTab(channelId: self.channelId, params: tab.params)
            guard generation == self.tabGenerations[key, default: 0] else { return }
            self.tabPages[key] = page
        } catch {
            guard generation == self.tabGenerations[key, default: 0], !(error is CancellationError) else { return }
            self.logger.error("Failed to load a YouTube channel tab: \(error.localizedDescription)")
            self.tabErrors[key] = LoadingError(from: error)
        }
    }

    private func bumpGeneration(for key: String) -> Int {
        let generation = self.tabGenerations[key, default: 0] + 1
        self.tabGenerations[key] = generation
        return generation
    }
}
