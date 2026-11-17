import SwiftUI

// MARK: - YouTubeGridZoom

/// Zoom for YouTube's video and playlist grids: View → Zoom In (⌘+, also ⌘=)
/// and Zoom Out (⌘−), and the toolbar's Zoom control. It applies on every
/// grid page (Home, Subscriptions, Explore, channels, playlists, History) but
/// not the watch page, Search, or Shorts, and never changes the rest of the
/// app's scale.
enum YouTubeGridZoom {
    /// The sizes zoom steps through, relative to the standard cards.
    static let levels: [Double] = [0.7, 0.8, 0.9, 1, 1.15, 1.3, 1.5, 1.75, 2]
    static let standard: Double = 1

    /// The next larger level, or nil at the largest.
    static func zoomedIn(from zoom: Double) -> Double? {
        self.levels.first { $0 > zoom + 0.001 }
    }

    /// The next smaller level, or nil at the smallest.
    static func zoomedOut(from zoom: Double) -> Double? {
        self.levels.last { $0 < zoom - 0.001 }
    }

    /// The level closest to a stored value, so an out-of-range or stale value
    /// still lands on a step.
    static func level(nearest zoom: Double) -> Double {
        self.levels.min { abs($0 - zoom) < abs($1 - zoom) } ?? self.standard
    }

    // MARK: Layout

    /// The adaptive grid every YouTube card page uses, scaled.
    static func columns(zoom: Double) -> [GridItem] {
        [GridItem(.adaptive(minimum: 210 * zoom, maximum: 320 * zoom), spacing: 16)]
    }

    /// Rail cards match the music video card width at the standard zoom.
    static func railCardWidth(zoom: Double) -> CGFloat {
        284 * zoom
    }

    /// Thumbnails decode larger only when cards grow, so zooming out never
    /// decodes them again.
    static func thumbnailSize(zoom: Double) -> CGSize {
        let scale = max(1, zoom)
        return CGSize(width: 320 * scale, height: 180 * scale)
    }

    // MARK: Where It Applies

    /// Whether the page on screen is a card grid that zoom changes.
    @MainActor
    static func isGridOnScreen(selection: YouTubeNavigationItem?) -> Bool {
        guard SettingsManager.shared.appSource == .video else { return false }
        if let top = YouTubePageRefresh.shared.store?.navigationPath.last {
            return self.isGridPage(top)
        }
        return selection.map(self.isGridPage) ?? false
    }

    static func isGridPage(_ route: YouTubeRoute) -> Bool {
        switch route {
        case .channel, .playlist: true
        case .watch: false
        }
    }

    static func isGridPage(_ item: YouTubeNavigationItem) -> Bool {
        switch item {
        case .home, .subscriptions, .explore, .likedVideos, .watchLater, .playlists, .history, .playlist: true
        case .search, .shorts: false
        }
    }

    // MARK: Actions

    @MainActor
    static func zoomIn() {
        let settings = SettingsManager.shared
        guard let level = self.zoomedIn(from: settings.youtubeGridZoom) else { return }
        withAnimation(AppAnimation.standard) { settings.youtubeGridZoom = level }
    }

    @MainActor
    static func zoomOut() {
        let settings = SettingsManager.shared
        guard let level = self.zoomedOut(from: settings.youtubeGridZoom) else { return }
        withAnimation(AppAnimation.standard) { settings.youtubeGridZoom = level }
    }

    @MainActor
    static func resetZoom() {
        withAnimation(AppAnimation.standard) { SettingsManager.shared.youtubeGridZoom = self.standard }
    }
}

// MARK: - YouTubeGridZoomCommands

/// View → Zoom In, Zoom Out, and Actual Size, enabled while a YouTube card
/// grid is on screen. ⌘0 already shows the main window, so Actual Size has no
/// shortcut.
struct YouTubeGridZoomCommands: Commands {
    let isGridOnScreen: Bool
    let zoom: Double

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button(String(localized: "Zoom In")) {
                YouTubeGridZoom.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!self.isGridOnScreen || YouTubeGridZoom.zoomedIn(from: self.zoom) == nil)

            Button(String(localized: "Zoom Out")) {
                YouTubeGridZoom.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!self.isGridOnScreen || YouTubeGridZoom.zoomedOut(from: self.zoom) == nil)

            Button(String(localized: "Actual Size")) {
                YouTubeGridZoom.resetZoom()
            }
            .disabled(!self.isGridOnScreen || self.zoom == YouTubeGridZoom.standard)
        }
    }
}

// MARK: - Equals Shortcut

extension View {
    /// ⌘= zooms in too, as in Safari: a menu matches ⌘+ only with Shift held,
    /// and = is the same key without it. Active while a grid is on screen.
    func youtubeGridZoomEqualsShortcut(isEnabled: Bool) -> some View {
        self.background {
            Button(String(localized: "Zoom In")) {
                YouTubeGridZoom.zoomIn()
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(!isEnabled)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}
