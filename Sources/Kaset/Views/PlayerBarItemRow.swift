import SwiftUI

// MARK: - PlayerBarItemSpacing

/// Gaps between player bar items: 6pt between two buttons, 8pt next to a
/// media details block (artwork, title text), as the bars always had.
enum PlayerBarItemSpacing {
    static let betweenButtons: CGFloat = 6
    static let nextToBlock: CGFloat = 8
    /// Width of a Space item, and the least a Flexible Space takes.
    static let space: CGFloat = 12
    /// Keeps the progress lane off the capsule's rounded end on a side with
    /// no items, matching the inset the options give it on the right.
    static let emptySideInset: CGFloat = 16

    static func between(_ first: Bool, _ second: Bool) -> CGFloat {
        first || second ? self.nextToBlock : self.betweenButtons
    }

    /// Total width of items with the given widths, in order, and the gaps
    /// between them.
    static func rowWidth(_ widths: [(width: CGFloat, isBlock: Bool)]) -> CGFloat {
        var total: CGFloat = 0
        for (index, item) in widths.enumerated() {
            if index > 0 {
                total += self.between(widths[index - 1].isBlock, item.isBlock)
            }
            total += item.width
        }
        return total
    }
}

// MARK: - PlayerBarSpace

/// A Space item: a fixed gap, or a flexible one that grows where the row
/// has room (the row above the timeline) and stays at its least elsewhere.
struct PlayerBarSpace: View {
    let isFlexible: Bool

    var body: some View {
        Group {
            if self.isFlexible {
                Spacer(minLength: PlayerBarItemSpacing.space)
            } else {
                Color.clear
                    .frame(width: PlayerBarItemSpacing.space)
            }
        }
        .frame(height: 0)
        .accessibilityHidden(true)
    }
}

// MARK: - PlayerBarRowID

/// Identity of an item in a row: the item and how many times it came before,
/// so repeated spaces stay distinct and a control keeps its identity (and
/// state) when an item before it shows or hides.
struct PlayerBarRowID<Item: Hashable>: Hashable {
    let item: Item
    let occurrence: Int

    static func ids(for items: [Item]) -> [Self] {
        var seen: [Item: Int] = [:]
        return items.map { item in
            let occurrence = seen[item, default: 0]
            seen[item] = occurrence + 1
            return Self(item: item, occurrence: occurrence)
        }
    }
}

// MARK: - PlayerBarItemRow

/// A row of player bar items with the bar's gaps between them. Pass only
/// items that draw something, or a hidden one leaves a stray gap.
struct PlayerBarItemRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    let isBlock: (Item) -> Bool
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        let ids = PlayerBarRowID.ids(for: self.items)
        HStack(spacing: 0) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                if index > 0 {
                    // No height, so the gap doesn't make the row taller than its items.
                    Color.clear
                        .frame(width: PlayerBarItemSpacing.between(self.isBlock(self.items[index - 1]), self.isBlock(id.item)), height: 0)
                        .accessibilityHidden(true)
                }
                self.content(id.item)
            }
        }
    }
}
