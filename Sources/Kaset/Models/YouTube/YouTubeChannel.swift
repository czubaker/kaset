import Foundation

// MARK: - YouTubeChannel

/// A YouTube channel as it appears in search results and on watch pages.
struct YouTubeChannel: Identifiable, Hashable {
    let channelId: String
    let name: String
    /// Channel handle, e.g. "@veritasium".
    let handle: String?
    /// Display subscriber count, e.g. "20.8M subscribers".
    let subscriberCountText: String?
    let descriptionSnippet: String?
    let thumbnailURL: URL?

    var id: String {
        self.channelId
    }

    init(
        channelId: String,
        name: String,
        handle: String? = nil,
        subscriberCountText: String? = nil,
        descriptionSnippet: String? = nil,
        thumbnailURL: URL? = nil
    ) {
        self.channelId = channelId
        self.name = name
        self.handle = handle
        self.subscriberCountText = subscriberCountText
        self.descriptionSnippet = descriptionSnippet
        self.thumbnailURL = thumbnailURL
    }
}

// MARK: - YouTubeChannelDetail

/// A channel page: metadata plus the videos visible on the landing tab.
struct YouTubeChannelDetail: Hashable {
    let channel: YouTubeChannel
    let videos: [YouTubeVideo]
    /// The channel's tabs Kaset can show (Home, Videos, Shorts, Live,
    /// Playlists), in the channel's order.
    var tabs: [YouTubeChannelTab] = []
}

// MARK: - YouTubeChannelTab

/// A tab of a channel page, opened by browsing the channel with its params.
struct YouTubeChannelTab: Hashable, Identifiable {
    enum Kind: Hashable {
        case home
        case videos
        case shorts
        case live
        /// Playlists, and the playlist-like Podcasts, Releases, and Courses.
        case playlists
    }

    let kind: Kind
    /// The tab's name as YouTube shows it, in the account's language.
    let title: String
    let params: String

    var id: String {
        self.params
    }
}

// MARK: - YouTubeChannelSortOption

/// A sort a channel tab offers, such as Latest, Popular, or Oldest. Picking
/// one reloads the tab through its continuation.
struct YouTubeChannelSortOption: Hashable, Identifiable {
    let title: String
    let continuation: String?
    let isSelected: Bool

    var id: String {
        self.title
    }
}

// MARK: - YouTubeChannelTabPage

/// A page of a channel tab: its videos, Shorts, or playlists, the sorts it
/// offers, and the token for the next page.
struct YouTubeChannelTabPage: Hashable {
    var videos: [YouTubeVideo] = []
    var shorts: [YouTubeVideo] = []
    var playlists: [YouTubePlaylist] = []
    var sortOptions: [YouTubeChannelSortOption] = []
    var continuation: String?
}
