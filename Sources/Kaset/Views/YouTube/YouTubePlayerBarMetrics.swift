import CoreGraphics

/// Widths of the YouTube player bar's sides, from the items they show. The
/// standard layout comes out at the widths the bar had before it was
/// customizable: 294pt for full details (141pt compact) and 210pt of options.
enum YouTubePlayerBarMetrics {
    static let leadingInset: CGFloat = 14
    static let trailingInset: CGFloat = 12
    /// Room left after a side's title text, as the bar always had.
    static let titleTrailingGap: CGFloat = 16
    /// What the progress lane and the gaps around it need once both sides
    /// are compact; below it the details side hides.
    static let minimumCenterWidth: CGFloat = 229
    /// Room the progress lane keeps beside the row above it: what the
    /// minimum center width leaves around the standard row (skip back,
    /// play/pause, skip forward, volume).
    static let centerRowMargin: CGFloat = 99

    static let thumbnailWidth: CGFloat = 57
    static let titleWidth: CGFloat = 129
    static let avatarSize: CGFloat = 24
    static let avatarTitleSpacing: CGFloat = 6
    /// `PlayerBarIconButton` and `PlayerBarIconMenu` are 28pt squares.
    static let buttonWidth: CGFloat = 28

    /// Whether the item is a media details block, which gets wider gaps.
    static func isBlock(_ item: YouTubePlayerBarItem) -> Bool {
        switch item {
        case .thumbnail, .videoInfo, .channelInfo: true
        default: false
        }
    }

    /// The item's width, or nil when it draws nothing at this size.
    static func width(of item: YouTubePlayerBarItem, compact: Bool) -> CGFloat? {
        switch item {
        case .thumbnail:
            self.thumbnailWidth
        case .videoInfo:
            compact ? nil : self.titleWidth
        case .channelInfo:
            compact ? self.avatarSize : self.avatarSize + self.avatarTitleSpacing + self.titleWidth
        case .space, .flexibleSpace:
            PlayerBarItemSpacing.space
        default:
            self.buttonWidth
        }
    }

    /// Whether the item hides from the leading side when the bar is too
    /// narrow for it: the video's details and rating, which the standard
    /// layout's leading side holds. Controls placed there stay.
    static func hidesWhenNarrow(_ item: YouTubePlayerBarItem) -> Bool {
        switch item {
        case .thumbnail, .videoInfo, .channelInfo, .like, .dislike: true
        default: false
        }
    }

    /// Width of the items in a row and the gaps between them, without insets.
    private static func rowWidth(_ items: [YouTubePlayerBarItem], compact: Bool) -> CGFloat {
        PlayerBarItemSpacing.rowWidth(items.compactMap { item in
            self.width(of: item, compact: compact).map { (width: $0, isBlock: self.isBlock(item)) }
        })
    }

    /// Width of one side showing `items` (already filtered to the ones shown
    /// right now), with its inset from the capsule. Zero for an empty side.
    static func sideWidth(_ items: [YouTubePlayerBarItem], area: PlayerBarArea, compact: Bool) -> CGFloat {
        guard items.contains(where: { self.width(of: $0, compact: compact) != nil }) else { return 0 }
        let inset = area == .leading ? self.leadingInset : self.trailingInset
        let hasTitle = !compact && items.contains { $0 == .videoInfo || $0 == .channelInfo }
        return inset + self.rowWidth(items, compact: compact) + (hasTitle ? self.titleTrailingGap : 0)
    }

    /// What the middle of the bar needs for the row above the timeline
    /// (already filtered to the items shown) and the lane around it.
    static func centerWidth(_ items: [YouTubePlayerBarItem]) -> CGFloat {
        max(self.minimumCenterWidth, self.rowWidth(items, compact: true) + self.centerRowMargin)
    }

    /// The bar width at or below which the leading side drops its details,
    /// so it can't collide with the transport controls.
    static func hiddenDetailsBreakpoint(
        leading: [YouTubePlayerBarItem],
        trailing: [YouTubePlayerBarItem],
        center: [YouTubePlayerBarItem]
    ) -> CGFloat {
        self.sideWidth(leading, area: .leading, compact: true)
            + self.sideWidth(trailing, area: .trailing, compact: true)
            + self.centerWidth(center)
    }

    /// The leading side below the breakpoint: its details gone, and nothing
    /// at all when only spaces would be left.
    static func narrowLeading(_ items: [YouTubePlayerBarItem]) -> [YouTubePlayerBarItem] {
        let kept = items.filter { !self.hidesWhenNarrow($0) }
        return kept.allSatisfy { $0 == .space || $0 == .flexibleSpace } ? [] : kept
    }
}
