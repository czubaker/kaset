import SwiftUI

// MARK: - WindowToolbar

/// The main window's toolbar: the items the source's layout puts there, in
/// order, from its own buttons (Refresh, Notifications, Command Bar, …) to
/// player bar items moved up from the bar. Space separates groups of buttons;
/// Flexible Space pushes the rest to the far end.
struct WindowToolbar<ZoomControl: View>: ToolbarContent {
    let source: AppSource
    let youtubePlayer: YouTubePlayerService
    let youtubeStore: YouTubeViewModelStore
    let hasPersonalAccount: Bool
    let supportsCommandBar: Bool
    let presentCommandBar: () -> Void
    @ViewBuilder let zoomControl: () -> ZoomControl

    var body: some ToolbarContent {
        switch self.source {
        case .video:
            ForEach(Self.entries(self.youtubeItems)) { entry in
                self.toolbarEntry(spacing: Self.spacing(entry.item)) {
                    self.youtubeView(entry.item)
                }
            }
        case .music:
            ForEach(Self.entries(self.musicItems)) { entry in
                self.toolbarEntry(spacing: Self.spacing(entry.item)) {
                    self.musicView(entry.item)
                }
            }
        }
    }

    // MARK: Items

    private var youtubeItems: [YouTubePlayerBarItem] {
        SettingsManager.shared.youtubePlayerBar.items(in: .toolbar).filter { item in
            switch item {
            case .refresh, .zoom, .customizeWatchPage, .customize, .space, .flexibleSpace: true
            case .notifications: self.hasPersonalAccount
            default: YouTubeToolbarItem.isShown(item, player: self.youtubePlayer, hasPersonalAccount: self.hasPersonalAccount)
            }
        }
    }

    private var musicItems: [MusicPlayerBarItem] {
        SettingsManager.shared.musicPlayerBar.items(in: .toolbar).filter { item in
            switch item {
            case .customize, .space, .flexibleSpace: true
            case .commandBar: self.supportsCommandBar
            default: MusicToolbarItem.isShown(item, hasPersonalAccount: self.hasPersonalAccount)
            }
        }
    }

    @ViewBuilder
    private func youtubeView(_ item: YouTubePlayerBarItem) -> some View {
        switch item {
        case .refresh:
            // Reloads the page on screen like a browser's.
            Button {
                YouTubePageRefresh.shared.request()
            } label: {
                Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
            }
            .help(String(localized: "Refresh Page (⇧⌘R)"))
            .accessibilityIdentifier(AccessibilityID.MainWindow.refreshButton)
        case .notifications:
            YouTubeNotificationsButton(viewModel: self.youtubeStore.notifications) { video in
                self.youtubeStore.navigationPath.append(.watch(video))
            }
        case .zoom:
            self.zoomControl()
        case .customizeWatchPage:
            Button {
                PlayerBarCustomization.shared.presentWatchPage()
            } label: {
                Label(String(localized: "Customize Watch Page…"), systemImage: "rectangle.and.text.magnifyingglass")
            }
            .help(String(localized: "Customize Watch Page…"))
        case .customize:
            self.customizeButton
        default:
            YouTubeToolbarItem(item: item)
        }
    }

    @ViewBuilder
    private func musicView(_ item: MusicPlayerBarItem) -> some View {
        switch item {
        case .commandBar:
            Button {
                self.presentCommandBar()
            } label: {
                Label(String(localized: "Command Bar"), systemImage: "sparkles")
            }
            .help(String(localized: "Open Command Bar (⌘K)"))
            .accessibilityIdentifier(AccessibilityID.MainWindow.aiButton)
        case .customize:
            self.customizeButton
        default:
            MusicToolbarItem(item: item)
        }
    }

    private var customizeButton: some View {
        Button {
            PlayerBarCustomization.shared.present(for: self.source)
        } label: {
            Label(String(localized: "Customize Toolbar and Player Bar…"), systemImage: "slider.horizontal.3")
        }
        .help(String(localized: "Customize Toolbar and Player Bar…"))
    }

    // MARK: Layout

    private enum Spacing {
        case fixed
        case flexible
    }

    private static func spacing(_ item: some PlayerBarItemKind) -> Spacing? {
        switch item.rawValue {
        case "space": .fixed
        case "flexibleSpace": .flexible
        default: nil
        }
    }

    @ToolbarContentBuilder
    private func toolbarEntry(spacing: Spacing?, @ViewBuilder content: () -> some View) -> some ToolbarContent {
        if let spacing {
            if #available(macOS 26.0, *) {
                ToolbarSpacer(spacing == .flexible ? .flexible : .fixed)
            }
        } else {
            ToolbarItem(placement: .automatic) {
                content()
            }
        }
    }

    private struct Entry<Item: PlayerBarItemKind>: Identifiable {
        let id: String
        let item: Item
    }

    /// By position, since spaces can repeat.
    private static func entries<Item: PlayerBarItemKind>(_ items: [Item]) -> [Entry<Item>] {
        items.enumerated().map { Entry(id: "\($0.offset)-\($0.element.rawValue)", item: $0.element) }
    }
}
