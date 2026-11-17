import Foundation

// MARK: - YouTubeSidebarSection

/// A section of the YouTube sidebar. Items reorder within their section.
enum YouTubeSidebarSection: String, CaseIterable {
    case main
    case discover
    case collection

    /// The section's items in their standard order.
    var standardItems: [YouTubeNavigationItem] {
        switch self {
        case .main: [.search, .home, .subscriptions]
        case .discover: [.explore, .shorts]
        case .collection: [.likedVideos, .watchLater, .history, .playlists]
        }
    }
}

// MARK: - YouTubeSidebarOrder

/// The order of the YouTube sidebar's items, which the user changes by
/// dragging them with ⌘ held. Stored as item IDs per section; an item a later
/// version adds goes to the end of its section, and an unknown ID is dropped.
struct YouTubeSidebarOrder: Codable, Equatable {
    private var orders: [String: [String]] = [:]

    static let standard = Self()

    func items(in section: YouTubeSidebarSection) -> [YouTubeNavigationItem] {
        let standard = section.standardItems
        let saved = (self.orders[section.rawValue] ?? []).compactMap { id in
            standard.first { $0.id == id }
        }
        var seen = Set<String>()
        return (saved + standard).filter { seen.insert($0.id).inserted }
    }

    /// Moves `item` before `target`, or to the end of the section when
    /// `target` is nil. Returns false when either isn't in `section`.
    @discardableResult
    mutating func move(
        _ item: YouTubeNavigationItem,
        before target: YouTubeNavigationItem?,
        in section: YouTubeSidebarSection
    ) -> Bool {
        var items = self.items(in: section)
        guard let from = items.firstIndex(of: item), item != target else { return false }
        if let target, !items.contains(target) {
            return false
        }
        items.remove(at: from)
        let to = target.flatMap { items.firstIndex(of: $0) } ?? items.endIndex
        items.insert(item, at: to)
        self.orders[section.rawValue] = items.map(\.id)
        return true
    }

    /// The section `item` belongs to, if any.
    static func section(of item: YouTubeNavigationItem) -> YouTubeSidebarSection? {
        YouTubeSidebarSection.allCases.first { $0.standardItems.contains(item) }
    }
}
