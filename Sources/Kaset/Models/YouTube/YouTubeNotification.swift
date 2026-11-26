import Foundation

// MARK: - YouTubeNotification

/// One entry of YouTube's notification inbox that opens a video or a Short:
/// a new upload, a live stream, and the like. Ported from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
struct YouTubeNotification: Identifiable, Hashable {
    let id: String
    /// e.g. "Veritasium uploaded: How To Slow Aging".
    let message: String
    /// e.g. "3 hours ago".
    let sentTimeText: String?
    /// The video's still, or the channel's avatar.
    let thumbnailURL: URL?
    let video: YouTubeVideo
    /// Whether YouTube has it as read.
    let isRead: Bool
}
