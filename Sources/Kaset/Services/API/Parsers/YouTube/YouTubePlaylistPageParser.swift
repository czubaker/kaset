import Foundation

/// Parses YouTube playlist pages (`browse` with a `VL…` browse ID).
///
/// Modern playlist pages render items as `lockupViewModel`s; the header
/// lives in `pageHeaderRenderer` view models. Collection is recursive so
/// both the legacy `playlistVideoRenderer` and lockup shapes work.
enum YouTubePlaylistPageParser {
    static func parse(_ data: [String: Any], playlistId: String) -> YouTubePlaylistDetail {
        var videos: [YouTubeVideo] = []
        var continuation: String?
        if let contents = data["contents"] {
            YouTubeFeedParser.collect(
                in: contents,
                videos: &videos,
                continuation: &continuation
            )
        }
        let deduplicated = YouTubeFeedParser.deduplicate(videos)

        let playlist = YouTubePlaylist(
            playlistId: playlistId,
            title: Self.title(of: data) ?? playlistId,
            channelName: nil,
            videoCountText: Self.videoCountText(of: data),
            thumbnailURL: deduplicated.first?.thumbnailURL,
            firstVideoId: deduplicated.first?.videoId
        )

        return YouTubePlaylistDetail(
            playlist: playlist,
            videos: deduplicated,
            isSavedToLibrary: Self.saveState(of: data, playlistId: playlistId)
        )
    }

    /// The header's Save playlist / Remove from Library toggle: a
    /// `toggleButtonViewModel` in `pageHeaderViewModel.actions` whose default
    /// button likes this playlist (`likeEndpoint.target.playlistId`), with
    /// `isToggled` once saved (verified with api-explorer, November 2026).
    static func saveState(of data: [String: Any], playlistId: String) -> Bool? {
        let id = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        return Self.findSaveToggle(in: data["header"] ?? [:], playlistId: id)
    }

    private static func findSaveToggle(in value: Any, playlistId: String) -> Bool? {
        if let dict = value as? [String: Any] {
            if let toggle = dict["toggleButtonViewModel"] as? [String: Any],
               let like = (((((toggle["defaultButtonViewModel"] as? [String: Any])?["buttonViewModel"]
                       as? [String: Any])?["onTap"] as? [String: Any])?["innertubeCommand"]
                   as? [String: Any])?["likeEndpoint"]) as? [String: Any],
               ((like["target"] as? [String: Any])?["playlistId"] as? String) == playlistId
            {
                return toggle["isToggled"] as? Bool ?? false
            }
            for nested in dict.values {
                if let found = Self.findSaveToggle(in: nested, playlistId: playlistId) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let found = Self.findSaveToggle(in: element, playlistId: playlistId) {
                    return found
                }
            }
        }
        return nil
    }

    // MARK: - Private

    private static func title(of data: [String: Any]) -> String? {
        // Microformat is the most stable source for the playlist title.
        let microformat = (
            (data["microformat"] as? [String: Any])?["microformatDataRenderer"]
                as? [String: Any]
        )?["title"] as? String
        if let microformat {
            return microformat
        }

        // Fall back to the page header view model.
        guard let header = data["header"] as? [String: Any] else { return nil }
        return Self.firstHeaderTitle(in: header)
    }

    private static func videoCountText(of data: [String: Any]) -> String? {
        guard let header = data["header"] else { return nil }
        return Self.firstText(in: header) { $0.localizedCaseInsensitiveContains("video") }
    }

    private static func firstHeaderTitle(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let dynamicText = dict["dynamicTextViewModel"] as? [String: Any],
               let content = (dynamicText["text"] as? [String: Any])?["content"] as? String
            {
                return content
            }
            for nested in dict.values {
                if let found = Self.firstHeaderTitle(in: nested) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let found = Self.firstHeaderTitle(in: element) {
                    return found
                }
            }
        }
        return nil
    }

    private static func firstText(
        in value: Any,
        where predicate: (String) -> Bool
    ) -> String? {
        if let dict = value as? [String: Any] {
            for key in ["content", "simpleText"] {
                if let text = dict[key] as? String, predicate(text) {
                    return text
                }
            }
            for nested in dict.values {
                if let found = firstText(in: nested, where: predicate) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let found = Self.firstText(in: element, where: predicate) {
                    return found
                }
            }
        }
        return nil
    }
}
