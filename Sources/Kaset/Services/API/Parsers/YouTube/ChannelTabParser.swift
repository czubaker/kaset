import Foundation

// MARK: - ChannelTabParser

/// Parses a channel page's tabs and the pages of one tab: a browse of the
/// channel with the tab's params, then its continuations. Verified against
/// api-explorer captures in November 2026 (see docs/api-discovery.md).
enum ChannelTabParser {
    /// The tabs Kaset can show, from any browse response of the channel.
    /// Kinds come from each tab's URL (`/videos`, `/streams`, …), since titles
    /// are localized.
    static func tabs(from data: [String: Any]) -> [YouTubeChannelTab] {
        self.tabRenderers(in: data).compactMap { renderer in
            guard let endpoint = renderer["endpoint"] as? [String: Any],
                  let params = (endpoint["browseEndpoint"] as? [String: Any])?["params"] as? String,
                  let title = renderer["title"] as? String ?? YouTubeItemParser.text(from: renderer["title"]),
                  let url = (
                      (endpoint["commandMetadata"] as? [String: Any])?["webCommandMetadata"] as? [String: Any]
                  )?["url"] as? String,
                  let kind = Self.kind(forURL: url)
            else { return nil }
            return YouTubeChannelTab(kind: kind, title: title, params: params)
        }
    }

    /// The selected tab's page from a browse of the channel with tab params.
    static func parsePage(_ data: [String: Any]) -> YouTubeChannelTabPage {
        let content = Self.tabRenderers(in: data).first { $0["selected"] as? Bool == true }?["content"] ?? data
        var page = Self.collect(in: content as Any)
        page.sortOptions = Self.sortOptions(in: content as Any)
        return page
    }

    /// A continuation of a tab: the next page (`appendContinuationItemsAction`)
    /// or a sort's reload (`reloadContinuationItemsCommand`, whose first
    /// action brings the sort chips with the new selection).
    static func parseContinuation(_ data: [String: Any]) -> YouTubeChannelTabPage {
        let actions = data["onResponseReceivedActions"] as? [[String: Any]] ?? []
        var items: [Any] = []
        for action in actions {
            let command = action["appendContinuationItemsAction"] as? [String: Any]
                ?? action["reloadContinuationItemsCommand"] as? [String: Any]
            items.append(contentsOf: command?["continuationItems"] as? [Any] ?? [])
        }
        var page = Self.collect(in: items)
        page.sortOptions = Self.sortOptions(in: items)
        return page
    }

    // MARK: Pieces

    static func kind(forURL url: String) -> YouTubeChannelTab.Kind? {
        switch url.split(separator: "/").last.map(String.init) {
        case "featured": .home
        case "videos": .videos
        case "shorts": .shorts
        case "streams": .live
        case "playlists", "podcasts", "releases", "courses": .playlists
        default: nil
        }
    }

    /// Latest / Popular / Oldest, from the grid header's chip bar (the
    /// `chipBarViewModel` YouTube serves now, or the older
    /// `feedFilterChipBarRenderer`).
    static func sortOptions(in value: Any) -> [YouTubeChannelSortOption] {
        if let bar = ResponseTreeSearch.firstDictionary(named: "chipBarViewModel", in: value) {
            return (bar["chips"] as? [[String: Any]] ?? []).compactMap { entry in
                guard let chip = entry["chipViewModel"] as? [String: Any],
                      let title = chip["text"] as? String
                else { return nil }
                let token = (
                    ((chip["tapCommand"] as? [String: Any])?["innertubeCommand"] as? [String: Any])?[
                        "continuationCommand"
                    ] as? [String: Any]
                )?["token"] as? String
                return YouTubeChannelSortOption(title: title, continuation: token, isSelected: chip["selected"] as? Bool == true)
            }
        }
        if let bar = ResponseTreeSearch.firstDictionary(named: "feedFilterChipBarRenderer", in: value) {
            return (bar["contents"] as? [[String: Any]] ?? []).compactMap { entry in
                guard let chip = entry["chipCloudChipRenderer"] as? [String: Any],
                      let title = YouTubeItemParser.text(from: chip["text"])
                else { return nil }
                let token = (
                    (chip["navigationEndpoint"] as? [String: Any])?["continuationCommand"] as? [String: Any]
                )?["token"] as? String
                return YouTubeChannelSortOption(title: title, continuation: token, isSelected: chip["isSelected"] as? Bool == true)
            }
        }
        return []
    }

    private static func collect(in value: Any) -> YouTubeChannelTabPage {
        var videos: [YouTubeVideo] = []
        var shorts: [YouTubeVideo] = []
        var continuation: String?
        YouTubeFeedParser.collect(in: value, videos: &videos, shorts: &shorts, continuation: &continuation)
        let playlists: [YouTubePlaylist] = if let dict = value as? [String: Any] {
            YouTubeFeedParser.collectPlaylists(dict)
        } else {
            YouTubeFeedParser.collectPlaylists(["items": value])
        }
        return YouTubeChannelTabPage(
            videos: YouTubeFeedParser.deduplicate(videos),
            shorts: YouTubeFeedParser.deduplicate(shorts),
            playlists: playlists,
            continuation: continuation
        )
    }

    private static func tabRenderers(in data: [String: Any]) -> [[String: Any]] {
        let tabs = (
            (data["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any]
        )?["tabs"] as? [[String: Any]] ?? []
        return tabs.compactMap { $0["tabRenderer"] as? [String: Any] }
    }
}
