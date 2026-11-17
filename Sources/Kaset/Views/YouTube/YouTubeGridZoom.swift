import SwiftUI

// MARK: - YouTubeHomeZoom

/// Zoom for YouTube Home's video cards: View → Zoom In (⌘+) and Zoom Out
/// (⌘−), and the toolbar's Zoom control. Only Home's cards change size; the
/// rest of the app keeps its scale.
enum YouTubeHomeZoom {
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

    /// Whether YouTube Home is the page on screen, the only one zoom changes.
    @MainActor
    static func isHomeOnScreen(selection: YouTubeNavigationItem?) -> Bool {
        SettingsManager.shared.appSource == .video
            && selection == .home
            && (YouTubePageRefresh.shared.store?.navigationPath.isEmpty ?? true)
    }

    @MainActor
    static func zoomIn() {
        let settings = SettingsManager.shared
        guard let level = self.zoomedIn(from: settings.youtubeHomeZoom) else { return }
        withAnimation(AppAnimation.standard) { settings.youtubeHomeZoom = level }
    }

    @MainActor
    static func zoomOut() {
        let settings = SettingsManager.shared
        guard let level = self.zoomedOut(from: settings.youtubeHomeZoom) else { return }
        withAnimation(AppAnimation.standard) { settings.youtubeHomeZoom = level }
    }

    @MainActor
    static func resetZoom() {
        withAnimation(AppAnimation.standard) { SettingsManager.shared.youtubeHomeZoom = self.standard }
    }
}

// MARK: - YouTubeHomeZoomCommands

/// View → Zoom In, Zoom Out, and Actual Size, enabled while YouTube Home is
/// on screen. ⌘0 already shows the main window, so Actual Size has no
/// shortcut.
struct YouTubeHomeZoomCommands: Commands {
    let isHomeOnScreen: Bool
    let zoom: Double

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button(String(localized: "Zoom In")) {
                YouTubeHomeZoom.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!self.isHomeOnScreen || YouTubeHomeZoom.zoomedIn(from: self.zoom) == nil)

            Button(String(localized: "Zoom Out")) {
                YouTubeHomeZoom.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!self.isHomeOnScreen || YouTubeHomeZoom.zoomedOut(from: self.zoom) == nil)

            Button(String(localized: "Actual Size")) {
                YouTubeHomeZoom.resetZoom()
            }
            .disabled(!self.isHomeOnScreen || self.zoom == YouTubeHomeZoom.standard)
        }
    }
}
