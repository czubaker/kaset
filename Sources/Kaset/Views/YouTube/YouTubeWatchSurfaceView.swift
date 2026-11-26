import SwiftUI
import WebKit

// MARK: - YouTubeWatchSurfaceView

/// Hosts the extracted YouTube video surface (the watch WebView) inside a
/// native view. Used by both the inline WatchView and the floating window;
/// whichever is on screen reparents the singleton WebView into itself.
struct YouTubeWatchSurfaceView: NSViewRepresentable {
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    /// When present, this host may claim the singleton WebView only while that
    /// video is still selected. Shorts pages overlap briefly during paging, so
    /// an outgoing page can otherwise update late and steal the WebView back
    /// from the newly active page.
    let expectedVideoId: String?

    /// Where this host shows the video. It claims the WebView only while the
    /// player's surface is there: the floating window closes a moment after
    /// playback docks inline, and its host would otherwise take the WebView
    /// back into the closing window, leaving the watch page black.
    let location: YouTubePlayerService.SurfaceLocation

    init(expectedVideoId: String? = nil, location: YouTubePlayerService.SurfaceLocation = .inline) {
        self.expectedVideoId = expectedVideoId
        self.location = location
    }

    func makeNSView(context _: Context) -> YouTubeWatchContainerView {
        let container = YouTubeWatchContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        return container
    }

    func updateNSView(_ nsView: YouTubeWatchContainerView, context _: Context) {
        let player = self.youtubePlayer
        let location = self.location
        let expectedVideoId = self.expectedVideoId
        nsView.claimSurface = { [weak nsView] in
            guard let nsView, player.surfaceLocation == location else { return }
            YouTubeWatchWebView.shared.ensureInHierarchy(
                container: nsView,
                expectedVideoId: expectedVideoId,
                selectedVideoId: player.currentVideo?.videoId
            )
        }
        // Read both here, even while the claim waits for the window, so
        // SwiftUI runs this update again when either changes: a Shorts page
        // can reach the window before its video is the selected one.
        let selectedVideoId = player.currentVideo?.videoId
        guard player.surfaceLocation == location, expectedVideoId == nil || expectedVideoId == selectedVideoId else {
            return
        }
        nsView.claimSurfaceIfOnScreen()
    }
}

// MARK: - YouTubeWatchSurfaceAttachment

@MainActor
enum YouTubeWatchSurfaceAttachment {
    @discardableResult
    static func claim(
        surface: NSView,
        in container: NSView,
        expectedVideoId: String?,
        currentVideoId: String?
    ) -> Bool {
        if let expectedVideoId, expectedVideoId != currentVideoId {
            return false
        }
        guard surface.superview !== container else { return true }
        surface.removeFromSuperview()
        container.addSubview(surface)
        return true
    }
}

// MARK: - YouTubeWatchContainerView

/// Custom NSView that keeps the WebView sized with the container.
final class YouTubeWatchContainerView: NSView {
    /// Moves the shared watch surface into this container. Runs only while
    /// the container is in a window: a navigation stack keeps covered pages
    /// alive, and updating, outside the window, and a covered watch page for
    /// the same video (left under the page that docking back from the pop-out
    /// pushes) would otherwise take the surface from the page on screen,
    /// leaving it black while the video plays. A page claims it again when it
    /// comes back into the window.
    var claimSurface: (() -> Void)?

    func claimSurfaceIfOnScreen() {
        guard self.window != nil else { return }
        self.claimSurface?()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.postsFrameChangedNotifications = true
        self.wantsLayer = true
        self.layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.claimSurfaceIfOnScreen()
    }

    override func layout() {
        super.layout()
        // Overscan the WebView slightly: fractional-point rounding between
        // SwiftUI's aspect-fitted frame and the page's 100vw video leaves
        // hairline black slivers at the edges otherwise. The container's
        // layer clips the overflow.
        for subview in self.subviews where subview is WKWebView {
            subview.frame = self.bounds.insetBy(dx: -1.5, dy: -1.5)
        }
    }
}
