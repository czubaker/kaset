import SwiftUI

// MARK: - PlayerBarCustomization

/// Presents the player bar customization sheet, from View → Customize Player
/// Bar… and the player bar's context menu, the way Finder customizes its
/// toolbar. Shared, since player bars sit on pages that don't inherit the
/// main window's environment.
///
/// The sheet belongs to the main window, so presenting it brings that window
/// forward (opening it if it was closed), including when the request comes
/// from the detached video window's bar.
@MainActor
@Observable
final class PlayerBarCustomization {
    static let shared = PlayerBarCustomization()

    var isPresented = false
    /// The source whose bar the sheet edits.
    private(set) var source: AppSource = .music
    /// Shows the main window, which hosts the sheet. Set by the app.
    @ObservationIgnored var showMainWindow: (() -> Void)?

    func present(for source: AppSource) {
        self.source = source
        self.isPresented = true
        self.showMainWindow?()
    }
}

// MARK: - PlayerBarCustomizationCommands

/// View → Customize Player Bar…, next to the toolbar commands as in Finder.
/// Edits the bar of the source on screen.
struct PlayerBarCustomizationCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(String(localized: "Customize Player Bar…")) {
                PlayerBarCustomization.shared.present(for: SettingsManager.shared.appSource)
            }
        }
    }
}

// MARK: - PlayerBarCustomizationSheet

/// Edits one source's player bar: drag items between the bar's sides, the
/// row above the timeline, YouTube's video settings menu, and the palette.
/// Every change shows on the real bar right away.
struct PlayerBarCustomizationSheet: View {
    let source: AppSource

    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Customize Player Bar", comment: "Title of the player bar customization sheet")
                    .font(.title2.bold())
                Text("Drag items into the player bar, or drag them out to remove them.", comment: "Player bar customization instructions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            switch self.source {
            case .music:
                PlayerBarCustomizationEditor(configuration: self.$settings.musicPlayerBar)
            case .video:
                PlayerBarCustomizationEditor(configuration: self.$settings.youtubePlayerBar)
            }

            HStack {
                Button(String(localized: "Restore Defaults")) {
                    withAnimation(AppAnimation.standard) {
                        switch self.source {
                        case .music: self.settings.musicPlayerBar = .standard
                        case .video: self.settings.youtubePlayerBar = .standard
                        }
                    }
                }
                Spacer()
                Button(String(localized: "Done")) {
                    self.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 980)
        // As in Finder, a bar item dropped anywhere off the bar comes off it.
        // The drop zones and the palette inside take their own drops first.
        .contentShape(.rect)
        .dropDestination(for: String.self) { payloads, _ in
            self.removeDroppedItem(payloads.first)
        }
    }

    /// Takes a bar item dropped outside every zone off the bar. A palette
    /// item dropped there does nothing.
    private func removeDroppedItem(_ encoded: String?) -> Bool {
        guard case let .placed(area, index) = encoded.flatMap(PlayerBarDragPayload.init) else { return false }
        withAnimation(AppAnimation.quick) {
            switch self.source {
            case .music: self.settings.musicPlayerBar.remove(from: area, at: index)
            case .video: self.settings.youtubePlayerBar.remove(from: area, at: index)
            }
        }
        return true
    }
}

// MARK: - PlayerBarDragPayload

/// What a drag carries: an item from the palette, or the item at a position
/// on the bar. Encoded as a string so it travels as plain text.
private enum PlayerBarDragPayload {
    case palette(rawValue: String)
    case placed(area: PlayerBarArea, index: Int)

    var encoded: String {
        switch self {
        case let .palette(rawValue): "palette|\(rawValue)"
        case let .placed(area, index): "placed|\(area.rawValue)|\(index)"
        }
    }

    init?(_ string: String) {
        let parts = string.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "palette" where parts.count == 2:
            self = .palette(rawValue: parts[1])
        case "placed" where parts.count == 3:
            guard let area = PlayerBarArea(rawValue: parts[1]), let index = Int(parts[2]) else { return nil }
            self = .placed(area: area, index: index)
        default:
            return nil
        }
    }
}

private extension PlayerBarConfiguration {
    /// Drops a dragged item into `area` before the item at `index`.
    mutating func drop(_ encoded: String, in area: PlayerBarArea, at index: Int?) -> Bool {
        switch PlayerBarDragPayload(encoded) {
        case let .palette(rawValue):
            guard let item = Item(rawValue: rawValue) else { return false }
            return self.add(item, to: area, at: index)
        case let .placed(source, sourceIndex):
            return self.move(from: source, at: sourceIndex, to: area, at: index)
        case nil:
            return false
        }
    }
}

// MARK: - PlayerBarCustomizationEditor

/// The bar preview and the palette for one source.
private struct PlayerBarCustomizationEditor<Item: PlayerBarItemKind>: View {
    @Binding var configuration: PlayerBarConfiguration<Item>

    private var hasSettingsMenu: Bool {
        Item.allCases.contains { $0.allowedAreas.contains(.settingsMenu) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                PlayerBarDropZone(area: .leading, configuration: self.$configuration)
                VStack(spacing: 6) {
                    PlayerBarDropZone(area: .center, configuration: self.$configuration)
                    // Where the timeline runs, under the center row.
                    Capsule()
                        .fill(.tertiary)
                        .frame(height: 4)
                        .padding(.horizontal, 8)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                PlayerBarDropZone(area: .trailing, configuration: self.$configuration)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            if self.hasSettingsMenu {
                HStack(spacing: 10) {
                    Label(String(localized: "Video Settings Menu"), systemImage: "gearshape")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    PlayerBarDropZone(area: .settingsMenu, configuration: self.$configuration)
                }
            }

            PlayerBarPalette(configuration: self.$configuration)
        }
        .animation(AppAnimation.quick, value: self.configuration)
    }
}

// MARK: - PlayerBarDropZone

/// One area of the bar preview. Dropping on an item inserts before it;
/// dropping on the free space after the items appends.
private struct PlayerBarDropZone<Item: PlayerBarItemKind>: View {
    let area: PlayerBarArea
    @Binding var configuration: PlayerBarConfiguration<Item>

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isTargeted = false
    @State private var targetedIndex: Int?

    var body: some View {
        let items = self.configuration.items(in: self.area)
        HStack(spacing: 4) {
            // By position: spaces can repeat.
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                PlayerBarItemChip(item: item, showsTitle: false)
                    .overlay(alignment: .leading) {
                        if self.targetedIndex == index {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: 3)
                                .offset(x: -4.5)
                        }
                    }
                    .draggable(PlayerBarDragPayload.placed(area: self.area, index: index).encoded) {
                        PlayerBarItemChip(item: item, showsTitle: true)
                    }
                    .dropDestination(for: String.self) { payloads, _ in
                        payloads.first.map { self.configuration.drop($0, in: self.area, at: index) } ?? false
                    } isTargeted: { targeted in
                        if targeted {
                            self.targetedIndex = index
                        } else if self.targetedIndex == index {
                            self.targetedIndex = nil
                        }
                    }
                    .contextMenu {
                        PlayerBarItemMenu(item: item, placement: (self.area, index), configuration: self.$configuration)
                    }
            }

            // Free space after the items; takes drops that append.
            Color.clear
                .frame(minWidth: items.isEmpty ? 120 : 12, maxWidth: self.area == .center ? .infinity : nil)
                .frame(height: 40)
                .contentShape(.rect)
                .dropDestination(for: String.self) { payloads, _ in
                    payloads.first.map { self.configuration.drop($0, in: self.area, at: nil) } ?? false
                } isTargeted: { self.isTargeted = $0 }
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    self.isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: self.isTargeted ? 2 : 1, dash: [4, 3])
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(self.area.title(in: self.layoutDirection))
    }
}

// MARK: - PlayerBarPalette

/// Items to add: those not on the bar, and spaces always. Dropping a bar
/// item here takes it off the bar.
private struct PlayerBarPalette<Item: PlayerBarItemKind>: View {
    @Binding var configuration: PlayerBarConfiguration<Item>

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Available Items", comment: "Header of the player bar customization palette")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 12) {
                ForEach(self.configuration.paletteItems, id: \.self) { item in
                    PlayerBarItemChip(item: item, showsTitle: true)
                        .draggable(PlayerBarDragPayload.palette(rawValue: item.rawValue).encoded) {
                            PlayerBarItemChip(item: item, showsTitle: true)
                        }
                        .contextMenu {
                            PlayerBarItemMenu(item: item, placement: nil, configuration: self.$configuration)
                        }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            }
            .dropDestination(for: String.self) { payloads, _ in
                guard case let .placed(area, index) = payloads.first.flatMap(PlayerBarDragPayload.init) else {
                    return false
                }
                self.configuration.remove(from: area, at: index)
                return true
            } isTargeted: { self.isTargeted = $0 }
        }
    }
}

// MARK: - PlayerBarItemMenu

/// Moves, adds, or removes an item without dragging.
private struct PlayerBarItemMenu<Item: PlayerBarItemKind>: View {
    let item: Item
    /// Where the item is on the bar; nil for a palette item.
    let placement: (area: PlayerBarArea, index: Int)?
    @Binding var configuration: PlayerBarConfiguration<Item>

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if let placement {
            let count = self.configuration.items(in: placement.area).count
            // Earlier in the row is to the right in right-to-left languages.
            let isRightToLeft = self.layoutDirection == .rightToLeft
            Button(isRightToLeft ? String(localized: "Move Right") : String(localized: "Move Left")) {
                self.configuration.move(from: placement.area, at: placement.index, to: placement.area, at: placement.index - 1)
            }
            .disabled(placement.index == 0)
            Button(isRightToLeft ? String(localized: "Move Left") : String(localized: "Move Right")) {
                self.configuration.move(from: placement.area, at: placement.index, to: placement.area, at: placement.index + 2)
            }
            .disabled(placement.index == count - 1)

            let destinations = PlayerBarArea.allCases.filter {
                $0 != placement.area && self.item.allowedAreas.contains($0)
            }
            if !destinations.isEmpty {
                Menu(String(localized: "Move To")) {
                    ForEach(destinations, id: \.self) { area in
                        Button(area.title(in: self.layoutDirection)) {
                            self.configuration.move(from: placement.area, at: placement.index, to: area)
                        }
                    }
                }
            }

            Divider()
            Button(String(localized: "Remove from Player Bar"), role: .destructive) {
                self.configuration.remove(from: placement.area, at: placement.index)
            }
        } else {
            let destinations = PlayerBarArea.allCases.filter { self.item.allowedAreas.contains($0) }
            Menu(String(localized: "Add To")) {
                ForEach(destinations, id: \.self) { area in
                    Button(area.title(in: self.layoutDirection)) {
                        self.configuration.add(self.item, to: area)
                    }
                }
            }
        }
    }
}

// MARK: - PlayerBarItemChip

/// An item as the sheet shows it: its symbol in a tile, wider for media
/// details, with its name below in the palette.
private struct PlayerBarItemChip<Item: PlayerBarItemKind>: View {
    let item: Item
    /// Palette chips show the name below a larger tile; bar chips are
    /// compact, so a full bar fits the preview.
    let showsTitle: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: self.item.systemImage)
                .font(.system(size: self.showsTitle ? 14 : 12, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: self.tileWidth, height: self.tileHeight)
                .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.separator)
                }
            if self.showsTitle {
                Text(self.item.title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .frame(width: 88)
            }
        }
        .contentShape(.rect)
        .help(self.item.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.item.title)
    }

    private var tileHeight: CGFloat {
        self.showsTitle ? 32 : 28
    }

    /// Media details blocks are wider on the real bar, so their tiles are too.
    private var tileWidth: CGFloat {
        let isBlock = !self.item.allowedAreas.contains(.center)
        switch (isBlock, self.showsTitle) {
        case (true, true): return 64
        case (true, false): return 48
        case (false, true): return 32
        case (false, false): return 28
        }
    }
}

// MARK: - Area Titles

extension PlayerBarArea {
    /// The area's name as it appears on screen: the leading side is on the
    /// right in right-to-left languages.
    func title(in direction: LayoutDirection) -> String {
        let isRightToLeft = direction == .rightToLeft
        switch self {
        case .leading: return isRightToLeft ? String(localized: "Right Side") : String(localized: "Left Side")
        case .center: return String(localized: "Center")
        case .trailing: return isRightToLeft ? String(localized: "Left Side") : String(localized: "Right Side")
        case .settingsMenu: return String(localized: "Video Settings Menu")
        }
    }
}
