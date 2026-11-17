import Foundation

// MARK: - YouTubePlayerBarDetailField

/// What one line of a YouTube player bar details block shows.
enum YouTubePlayerBarDetailField: String, Codable, CaseIterable, Identifiable {
    case title
    case channel
    case views
    case date
    case viewsAndDate
    case subscribers

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .title: String(localized: "Video Title")
        case .channel: String(localized: "Channel")
        case .views: String(localized: "Views")
        case .date: String(localized: "Upload Date")
        case .viewsAndDate: String(localized: "Views and Date")
        case .subscribers: String(localized: "Subscribers")
        }
    }
}

// MARK: - YouTubePlayerBarDetailLines

/// The two lines of a details block. The first always shows something; the
/// second can be left empty.
struct YouTubePlayerBarDetailLines: Equatable {
    var first: YouTubePlayerBarDetailField
    var second: YouTubePlayerBarDetailField?

    /// The title over the channel, as the bar always showed.
    static let standard = Self(first: .title, second: .channel)

    var fields: [YouTubePlayerBarDetailField] {
        [self.first] + (self.second.map { [$0] } ?? [])
    }
}

// MARK: Codable

extension YouTubePlayerBarDetailLines: Codable {
    private enum CodingKeys: String, CodingKey {
        case first
        case second
    }

    /// Unknown fields (from another version) fall back to the standard line.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let first = try container.decodeIfPresent(String.self, forKey: .first)
            .flatMap(YouTubePlayerBarDetailField.init(rawValue:))
        let second = try container.decodeIfPresent(String.self, forKey: .second)
        self.first = first ?? Self.standard.first
        if let second {
            self.second = YouTubePlayerBarDetailField(rawValue: second) ?? Self.standard.second
        } else {
            self.second = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.first.rawValue, forKey: .first)
        try container.encodeIfPresent(self.second?.rawValue, forKey: .second)
    }
}

// MARK: - YouTubePlayerBarDetails

/// The lines of the YouTube player bar's two details blocks: Details (text
/// alone) and Avatar and Details. Each block keeps its own lines.
struct YouTubePlayerBarDetails: Codable, Equatable {
    var videoInfo: YouTubePlayerBarDetailLines = .standard
    var channelInfo: YouTubePlayerBarDetailLines = .standard

    static let standard = Self()

    /// The lines of `item`, or nil for an item without any.
    func lines(for item: YouTubePlayerBarItem) -> YouTubePlayerBarDetailLines? {
        switch item {
        case .videoInfo: self.videoInfo
        case .channelInfo: self.channelInfo
        default: nil
        }
    }

    mutating func setLines(_ lines: YouTubePlayerBarDetailLines, for item: YouTubePlayerBarItem) {
        switch item {
        case .videoInfo: self.videoInfo = lines
        case .channelInfo: self.channelInfo = lines
        default: break
        }
    }

    /// The fields that the details blocks on `layout` show.
    func fields(on layout: PlayerBarConfiguration<YouTubePlayerBarItem>) -> Set<YouTubePlayerBarDetailField> {
        var fields = Set<YouTubePlayerBarDetailField>()
        for area in [PlayerBarArea.leading, .center, .trailing] {
            for item in layout.items(in: area) {
                fields.formUnion(self.lines(for: item)?.fields ?? [])
            }
        }
        return fields
    }

    private enum CodingKeys: String, CodingKey {
        case videoInfo
        case channelInfo
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.videoInfo = try container.decodeIfPresent(YouTubePlayerBarDetailLines.self, forKey: .videoInfo) ?? .standard
        self.channelInfo = try container.decodeIfPresent(YouTubePlayerBarDetailLines.self, forKey: .channelInfo) ?? .standard
    }
}
