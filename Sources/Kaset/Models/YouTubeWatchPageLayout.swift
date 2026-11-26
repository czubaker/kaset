import Foundation

// MARK: - YouTubeWatchPageElement

/// A part of the YouTube watch page that can be hidden.
enum YouTubeWatchPageElement: String, CaseIterable, Identifiable {
    case title
    case views
    case date
    case channel
    case subscriberCount
    case subscribeButton
    case videoDescription
    case chapters
    case comments
    case related

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .title: String(localized: "Video Title")
        case .views: String(localized: "Views")
        case .date: String(localized: "Upload Date")
        case .channel: String(localized: "Channel Avatar and Name")
        case .subscriberCount: String(localized: "Subscribers")
        case .subscribeButton: String(localized: "Subscribe Button")
        case .videoDescription: String(localized: "Description")
        case .chapters: String(localized: "Chapters")
        case .comments: String(localized: "Comments")
        case .related: String(localized: "Related Videos")
        }
    }

    /// The parts under the video, in page order; Related Videos sits beside it.
    static let belowVideo: [Self] = [
        .title, .views, .date, .channel, .subscriberCount, .subscribeButton, .videoDescription, .chapters, .comments,
    ]
}

// MARK: - YouTubeWatchPageLayout

/// Which parts of the YouTube watch page show. Everything shows until the user
/// hides it, and an element added in a later version shows too.
struct YouTubeWatchPageLayout: Equatable {
    var hiddenElements: Set<YouTubeWatchPageElement> = []
    /// Hide what the player bar already shows, such as the Subscribe button
    /// once it's on the bar.
    var hidesPlayerBarItems = false

    static let standard = Self()

    /// Whether `element` shows, given what the YouTube player bar shows.
    func shows(
        _ element: YouTubeWatchPageElement,
        playerBar: PlayerBarConfiguration<YouTubePlayerBarItem>,
        details: YouTubePlayerBarDetails
    ) -> Bool {
        guard !self.hiddenElements.contains(element) else { return false }
        guard self.hidesPlayerBarItems else { return true }
        return !Self.playerBarShows(element, playerBar: playerBar, details: details)
    }

    /// Whether the player bar shows `element`, wherever it sits on the bar.
    static func playerBarShows(
        _ element: YouTubeWatchPageElement,
        playerBar: PlayerBarConfiguration<YouTubePlayerBarItem>,
        details: YouTubePlayerBarDetails
    ) -> Bool {
        let fields = details.fields(on: playerBar)
        switch element {
        case .title:
            return fields.contains(.title)
        case .views:
            return fields.contains(.views) || fields.contains(.viewsAndDate)
        case .date:
            return fields.contains(.date) || fields.contains(.viewsAndDate)
        case .channel:
            return playerBar.contains(.channelAvatar) || playerBar.contains(.channelInfo) || fields.contains(.channel)
        case .subscriberCount:
            return fields.contains(.subscribers)
        case .subscribeButton:
            return playerBar.contains(.subscribe) || playerBar.contains(.subscribeIcon)
        case .videoDescription, .chapters, .comments, .related:
            return false
        }
    }
}

// MARK: Codable

extension YouTubeWatchPageLayout: Codable {
    private enum CodingKeys: String, CodingKey {
        case hiddenElements
        case hidesPlayerBarItems
    }

    /// Unknown elements (from another version) are dropped.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hidden = try container.decodeIfPresent([String].self, forKey: .hiddenElements) ?? []
        self.hiddenElements = Set(hidden.compactMap(YouTubeWatchPageElement.init(rawValue:)))
        self.hidesPlayerBarItems = try container.decodeIfPresent(Bool.self, forKey: .hidesPlayerBarItems) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.hiddenElements.map(\.rawValue).sorted(), forKey: .hiddenElements)
        try container.encode(self.hidesPlayerBarItems, forKey: .hidesPlayerBarItems)
    }
}
