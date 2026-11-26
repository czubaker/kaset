import Foundation

/// Parses YouTube `search` responses.
///
/// June 2026 renderer mix (confirmed via api-explorer):
/// - Videos: legacy `videoRenderer`
/// - Channels: legacy `channelRenderer`
/// - Playlists: new `lockupViewModel` (`LOCKUP_CONTENT_TYPE_PLAYLIST`)
/// - Shorts shelves: `shortsLockupViewModel` (intentionally skipped)
enum YouTubeSearchParser {
    /// Parses a full search response.
    static func parse(_ data: [String: Any]) -> YouTubeSearchResponse {
        var response = YouTubeSearchResponse.empty

        let sections = Self.primarySections(of: data)
        for section in sections {
            if let itemSection = section["itemSectionRenderer"] as? [String: Any],
               let items = itemSection["contents"] as? [[String: Any]]
            {
                for item in items {
                    Self.append(item, to: &response)
                }
            } else if response.continuation == nil,
                      let continuationItem = section["continuationItemRenderer"] as? [String: Any]
            {
                response.continuation = YouTubeFeedParser.token(
                    fromContinuationItem: continuationItem
                )
            }
        }

        response.filterGroups = Self.filterGroups(in: data)
        return response
    }

    /// The filter dialog's groups: `header.searchHeaderRenderer
    /// .searchFilterButton…openPopupAction.popup.searchFilterOptionsDialogRenderer
    /// .groups[].searchFilterGroupRenderer`, each `searchFilterRenderer` with a
    /// label, `FILTER_STATUS_SELECTED` for the one in effect, and
    /// `navigationEndpoint.searchEndpoint.params` (percent-encoded) for the
    /// others (verified with api-explorer, November 2026). YouTube lists
    /// Type first, which Kaset offers as its own tabs, so it's left out.
    /// Ported in spirit from KasetPlus (github.com/Yoddikko/kasetPlus, MIT).
    static func filterGroups(in data: [String: Any]) -> [YouTubeSearchFilterGroup] {
        let dialog = ((((((data["header"] as? [String: Any])?["searchHeaderRenderer"] as? [String: Any])?[
            "searchFilterButton"
        ] as? [String: Any])?["buttonRenderer"] as? [String: Any])?["command"] as? [String: Any])?[
            "openPopupAction"
        ] as? [String: Any])?["popup"] as? [String: Any]
        let groups = ((dialog?["searchFilterOptionsDialogRenderer"] as? [String: Any])?["groups"] as? [[String: Any]]) ?? []
        return groups.dropFirst().compactMap { group in
            guard let renderer = group["searchFilterGroupRenderer"] as? [String: Any],
                  let title = YouTubeItemParser.text(from: renderer["title"])
            else { return nil }
            let options: [YouTubeSearchFilterGroup.Option] = (renderer["filters"] as? [[String: Any]] ?? []).compactMap { filter in
                guard let option = filter["searchFilterRenderer"] as? [String: Any],
                      let label = YouTubeItemParser.text(from: option["label"])
                else { return nil }
                let rawParams = ((option["navigationEndpoint"] as? [String: Any])?["searchEndpoint"] as? [String: Any])?[
                    "params"
                ] as? String
                return YouTubeSearchFilterGroup.Option(
                    label: label,
                    params: rawParams.map { $0.removingPercentEncoding ?? $0 },
                    isSelected: option["status"] as? String == "FILTER_STATUS_SELECTED"
                )
            }
            return options.isEmpty ? nil : YouTubeSearchFilterGroup(title: title, options: options)
        }
    }

    /// Parses a search continuation response.
    static func parseContinuation(_ data: [String: Any]) -> YouTubeSearchResponse {
        var response = YouTubeSearchResponse.empty
        let actions = data["onResponseReceivedCommands"] as? [[String: Any]]
            ?? data["onResponseReceivedActions"] as? [[String: Any]]
            ?? []

        for action in actions {
            let items = (action["appendContinuationItemsAction"] as? [String: Any])?["continuationItems"]
                as? [[String: Any]] ?? []
            for sectionItem in items {
                if let itemSection = sectionItem["itemSectionRenderer"] as? [String: Any],
                   let items = itemSection["contents"] as? [[String: Any]]
                {
                    for item in items {
                        Self.append(item, to: &response)
                    }
                } else if response.continuation == nil,
                          let continuationItem = sectionItem["continuationItemRenderer"]
                          as? [String: Any]
                {
                    response.continuation = YouTubeFeedParser.token(
                        fromContinuationItem: continuationItem
                    )
                }
            }
        }

        return response
    }

    // MARK: - Private

    /// The primary result sections
    /// (`contents.twoColumnSearchResultsRenderer.primaryContents.sectionListRenderer.contents`).
    private static func primarySections(of data: [String: Any]) -> [[String: Any]] {
        let sectionList = (
            (
                (data["contents"] as? [String: Any])?["twoColumnSearchResultsRenderer"]
                    as? [String: Any]
            )?["primaryContents"] as? [String: Any]
        )?["sectionListRenderer"] as? [String: Any]
        return sectionList?["contents"] as? [[String: Any]] ?? []
    }

    /// Dispatches one result item into the right bucket.
    private static func append(_ item: [String: Any], to response: inout YouTubeSearchResponse) {
        if let video = YouTubeItemParser.video(fromAnyItem: item) {
            response.videos.append(video)
            return
        }

        if let channelRenderer = item["channelRenderer"] as? [String: Any],
           let channel = YouTubeItemParser.channel(fromChannelRenderer: channelRenderer)
        {
            response.channels.append(channel)
            return
        }

        if let lockup = item["lockupViewModel"] as? [String: Any],
           let playlist = YouTubeItemParser.playlist(fromLockup: lockup)
        {
            response.playlists.append(playlist)
        }
    }
}
