import Foundation

// MARK: - PlayerBarArea

/// Where a customizable player bar item can sit.
enum PlayerBarArea: String, Codable, CaseIterable, Sendable {
    /// The media details side of the bar.
    case leading
    /// The row of buttons above the timeline.
    case center
    /// The options side of the bar.
    case trailing
    /// Inside the YouTube video settings (gear) menu instead of on the bar.
    case settingsMenu
    /// The window's toolbar, at the top of the main window.
    case toolbar

    /// The areas of the player bar itself, the settings menu included.
    static let barAreas: [Self] = [.leading, .center, .trailing, .settingsMenu]
}

// MARK: - PlayerBarItemKind

/// The customizable items of one source's player bar.
protocol PlayerBarItemKind: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    /// Name shown in the customization sheet.
    var title: String { get }
    /// Symbol shown for the item in the customization sheet.
    var systemImage: String { get }
    /// Areas the item may be placed in.
    var allowedAreas: Set<PlayerBarArea> { get }
    /// Whether the item can appear more than once, like a space. Every other
    /// item appears at most once.
    var isRepeatable: Bool { get }
    /// The window toolbar as it was before it was customized here.
    static var standardToolbar: [Self] { get }
}

// MARK: - PlayerBarConfiguration

/// Which items a player bar and the window toolbar show, and where.
///
/// Persisted as item raw values per area, so items added or removed in later
/// versions decode without failing: unknown ones are dropped, and new ones
/// stay off the bar until the user adds them. A layout saved before the
/// toolbar was part of it gets the standard toolbar.
struct PlayerBarConfiguration<Item: PlayerBarItemKind>: Equatable, Sendable {
    private(set) var leading: [Item] = []
    private(set) var center: [Item] = []
    private(set) var trailing: [Item] = []
    private(set) var settingsMenu: [Item] = []
    private(set) var toolbar: [Item] = []

    /// Builds a configuration, dropping repeats of items that can't repeat
    /// and items not allowed in the area they're listed in.
    init(leading: [Item], center: [Item], trailing: [Item], settingsMenu: [Item] = [], toolbar: [Item] = []) {
        let listed: [(PlayerBarArea, [Item])] = [
            (.leading, leading),
            (.center, center),
            (.trailing, trailing),
            (.settingsMenu, settingsMenu),
            (.toolbar, toolbar),
        ]
        for (area, items) in listed {
            for item in items where item.allowedAreas.contains(area) && (item.isRepeatable || !self.contains(item)) {
                self.modify(area) { $0.append(item) }
            }
        }
    }

    func items(in area: PlayerBarArea) -> [Item] {
        switch area {
        case .leading: self.leading
        case .center: self.center
        case .trailing: self.trailing
        case .settingsMenu: self.settingsMenu
        case .toolbar: self.toolbar
        }
    }

    func contains(_ item: Item) -> Bool {
        self.area(of: item) != nil
    }

    /// Whether the player bar shows the item (not the toolbar).
    func isOnBar(_ item: Item) -> Bool {
        PlayerBarArea.barAreas.contains { self.items(in: $0).contains(item) }
    }

    /// Where the item is, its first occurrence for a repeatable one.
    func area(of item: Item) -> PlayerBarArea? {
        PlayerBarArea.allCases.first { self.items(in: $0).contains(item) }
    }

    /// Items the palette offers: those not placed yet, and repeatable ones
    /// always. In declaration order.
    var paletteItems: [Item] {
        Item.allCases.filter { $0.isRepeatable || !self.contains($0) }
    }

    /// Adds `item` to `area` before the item at `index` (the end when nil or
    /// past it). A repeatable item is added again; any other item already
    /// placed moves from where it was. Returns false, changing nothing, when
    /// the item isn't allowed there.
    @discardableResult
    mutating func add(_ item: Item, to area: PlayerBarArea, at index: Int? = nil) -> Bool {
        if !item.isRepeatable,
           let current = self.area(of: item),
           let currentIndex = self.items(in: current).firstIndex(of: item)
        {
            return self.move(from: current, at: currentIndex, to: area, at: index)
        }
        guard item.allowedAreas.contains(area) else { return false }
        self.modify(area) { items in
            items.insert(item, at: min(max(index ?? Int.max, 0), items.count))
        }
        return true
    }

    /// Moves the item at `sourceIndex` in `source` to `area`, before the item
    /// at `index` there (the end when nil or past it). Returns false,
    /// changing nothing, when there is no such item or it isn't allowed there.
    @discardableResult
    mutating func move(from source: PlayerBarArea, at sourceIndex: Int, to area: PlayerBarArea, at index: Int? = nil) -> Bool {
        let sourceItems = self.items(in: source)
        guard sourceItems.indices.contains(sourceIndex) else { return false }
        let item = sourceItems[sourceIndex]
        guard item.allowedAreas.contains(area) else { return false }
        var target = index ?? Int.max
        self.modify(source) { $0.remove(at: sourceIndex) }
        // Taking it out from earlier in the same area shifts the target left.
        if source == area, sourceIndex < target {
            target -= 1
        }
        self.modify(area) { items in
            items.insert(item, at: min(max(target, 0), items.count))
        }
        return true
    }

    /// Takes the item at `index` in `area` off the bar.
    mutating func remove(from area: PlayerBarArea, at index: Int) {
        self.modify(area) { items in
            if items.indices.contains(index) {
                items.remove(at: index)
            }
        }
    }

    private mutating func modify(_ area: PlayerBarArea, _ change: (inout [Item]) -> Void) {
        switch area {
        case .leading: change(&self.leading)
        case .center: change(&self.center)
        case .trailing: change(&self.trailing)
        case .settingsMenu: change(&self.settingsMenu)
        case .toolbar: change(&self.toolbar)
        }
    }
}

// MARK: Codable

extension PlayerBarConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case leading
        case center
        case trailing
        case settingsMenu
        case toolbar
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decode(_ key: CodingKeys) throws -> [Item] {
            let rawValues = try container.decodeIfPresent([String].self, forKey: key) ?? []
            return rawValues.compactMap(Item.init(rawValue:))
        }
        try self.init(
            leading: decode(.leading),
            center: decode(.center),
            trailing: decode(.trailing),
            settingsMenu: decode(.settingsMenu),
            toolbar: container.contains(.toolbar) ? decode(.toolbar) : Item.standardToolbar
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.leading.map(\.rawValue), forKey: .leading)
        try container.encode(self.center.map(\.rawValue), forKey: .center)
        try container.encode(self.trailing.map(\.rawValue), forKey: .trailing)
        try container.encode(self.settingsMenu.map(\.rawValue), forKey: .settingsMenu)
        try container.encode(self.toolbar.map(\.rawValue), forKey: .toolbar)
    }
}
