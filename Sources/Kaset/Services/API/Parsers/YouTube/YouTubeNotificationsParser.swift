import Foundation

// MARK: - YouTubeNotificationsParser

/// Parses `notification/get_notification_menu`: a `multiPageMenuRenderer`
/// with one `notificationRenderer` per entry, each with `shortMessage`,
/// `sentTimeText`, `read`, a thumbnail, and a `navigationEndpoint` that is a
/// `watchEndpoint` (videos), a `reelWatchEndpoint` (Shorts), or something
/// else such as a comment (verified with api-explorer, November 2026). Only
/// videos and Shorts are kept. Ported from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT), with Shorts added.
enum YouTubeNotificationsParser {
    static func parse(_ data: [String: Any]) -> [YouTubeNotification] {
        var renderers: [[String: Any]] = []
        Self.collectRenderers(in: data, into: &renderers)
        var seen = Set<String>()
        return renderers.enumerated()
            .compactMap { index, renderer in Self.notification(from: renderer, fallbackId: index) }
            .filter { seen.insert($0.id).inserted }
    }

    private static func notification(from renderer: [String: Any], fallbackId: Int) -> YouTubeNotification? {
        guard let message = YouTubeItemParser.text(from: renderer["shortMessage"])
            ?? YouTubeItemParser.text(from: renderer["longMessage"]),
            let endpoint = renderer["navigationEndpoint"] as? [String: Any]
        else { return nil }

        let videoId: String
        let isShort: Bool
        if let watch = endpoint["watchEndpoint"] as? [String: Any], let id = watch["videoId"] as? String, !id.isEmpty {
            videoId = id
            isShort = false
        } else if let reel = endpoint["reelWatchEndpoint"] as? [String: Any], let id = reel["videoId"] as? String, !id.isEmpty {
            videoId = id
            isShort = true
        } else {
            return nil
        }

        let thumbnailURL = YouTubeItemParser.thumbnailURL(fromThumbnail: renderer["videoThumbnail"])
            ?? YouTubeItemParser.thumbnailURL(fromThumbnail: renderer["thumbnail"])
        return YouTubeNotification(
            id: renderer["notificationId"] as? String ?? "notification-\(fallbackId)",
            message: message,
            sentTimeText: YouTubeItemParser.text(from: renderer["sentTimeText"]),
            thumbnailURL: thumbnailURL,
            video: YouTubeVideo(videoId: videoId, title: message, thumbnailURL: thumbnailURL, isShort: isShort),
            isRead: renderer["read"] as? Bool ?? false
        )
    }

    private static func collectRenderers(in value: Any, into result: inout [[String: Any]]) {
        if let dict = value as? [String: Any] {
            if let renderer = dict["notificationRenderer"] as? [String: Any] {
                result.append(renderer)
            }
            for nested in dict.values {
                Self.collectRenderers(in: nested, into: &result)
            }
        } else if let array = value as? [Any] {
            for element in array {
                Self.collectRenderers(in: element, into: &result)
            }
        }
    }
}
