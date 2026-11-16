import SwiftUI

// MARK: - YouTubeVideoContextMenu

/// A video card's context menu, in line with the overflow menu on youtube.com:
/// Add to Watch Later and Add to Playlist when signed in, then the card's
/// "Not interested" / "Don't recommend channel" entries where the page
/// handles them. A card with nothing to offer gets no menu.
struct YouTubeVideoContextMenu: ViewModifier {
    let video: YouTubeVideo
    /// Sends a recommendation-feedback action; nil where the page can't.
    let sendFeedback: ((YouTubeFeedbackAction) -> Void)?

    @Environment(AuthService.self) private var authService

    func body(content: Content) -> some View {
        let canSave = self.authService.hasPersonalAccount
        let feedbackActions = self.sendFeedback == nil ? [] : self.video.feedbackActions
        if !canSave, feedbackActions.isEmpty {
            content
        } else {
            content.contextMenu {
                if canSave {
                    Button {
                        Task { await YouTubeVideoActions.shared.saveToWatchLater(self.video) }
                    } label: {
                        Label(String(localized: "Add to Watch Later"), systemImage: "clock")
                    }
                    YouTubeAddToPlaylistMenu(video: self.video)
                }

                if !feedbackActions.isEmpty {
                    if canSave {
                        Divider()
                    }
                    ForEach(feedbackActions, id: \.kind) { action in
                        Button {
                            self.sendFeedback?(action)
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                }
            }
        }
    }
}

extension View {
    /// Attaches the video context menu for `video`. Pass `sendFeedback` on
    /// pages that can drop a card after "Not interested" / "Don't recommend
    /// channel".
    func youtubeVideoContextMenu(
        for video: YouTubeVideo,
        sendFeedback: ((YouTubeFeedbackAction) -> Void)? = nil
    ) -> some View {
        self.modifier(YouTubeVideoContextMenu(video: video, sendFeedback: sendFeedback))
    }
}

// MARK: - YouTubeAddToPlaylistMenu

/// The user's playlists, loaded each time the context menu opens. Playlists
/// that already hold the video show a checkmark and can't be picked again.
private struct YouTubeAddToPlaylistMenu: View {
    let video: YouTubeVideo

    /// The latest list; kept while a newer one loads, since an open menu
    /// doesn't redraw.
    @State private var options: [AddToPlaylistOption]?
    @State private var didFail = false
    @State private var isLoading = false

    var body: some View {
        Menu {
            if let options = self.options {
                if options.isEmpty {
                    Label(String(localized: "No Playlists"), systemImage: "list.and.film")
                } else {
                    ForEach(options) { option in
                        Button {
                            Task { await self.add(to: option) }
                        } label: {
                            Label(option.title, systemImage: option.isSelected ? "checkmark.circle.fill" : "list.and.film")
                        }
                        .disabled(option.isSelected)
                    }
                }
            } else if self.didFail {
                Button {
                    Task { await self.loadPlaylists() }
                } label: {
                    Label(String(localized: "Retry Loading Playlists"), systemImage: "arrow.clockwise")
                }
            } else {
                Label(String(localized: "Loading Playlists…"), systemImage: "hourglass")
            }
        } label: {
            Label(String(localized: "Add to Playlist"), systemImage: "text.badge.plus")
        }
        // Load as the context menu is built, not when the submenu opens: menus
        // are largely snapshotted while open, so a late load would leave
        // "Loading Playlists…" until the menu is reopened.
        .task {
            await self.loadPlaylists()
        }
    }

    private func loadPlaylists() async {
        // Set before the first suspension, so overlapping calls send one request.
        guard !self.isLoading else { return }
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            self.options = try await YouTubeVideoActions.shared.playlistOptions(for: self.video)
            self.didFail = false
        } catch is CancellationError {
            // Closing the menu cancels the load; the next open tries again.
        } catch {
            DiagnosticsLogger.ui.error("Failed to load YouTube playlists: \(error.localizedDescription)")
            // A list from an earlier open stays usable.
            self.didFail = self.options == nil
        }
    }

    /// Adds the video, then checks the playlist off so the next open (which
    /// shows this list until the refresh lands) can't add it twice.
    private func add(to option: AddToPlaylistOption) async {
        guard await YouTubeVideoActions.shared.addToPlaylist(self.video, playlist: option) else { return }
        self.options = self.options?.map { $0.playlistId == option.playlistId ? $0.selected() : $0 }
    }
}

private extension AddToPlaylistOption {
    /// The same playlist, marked as holding the video.
    func selected() -> Self {
        Self(
            playlistId: self.playlistId,
            title: self.title,
            subtitle: self.subtitle,
            thumbnailURL: self.thumbnailURL,
            isSelected: true,
            privacyStatus: self.privacyStatus
        )
    }
}

// MARK: - YouTubeVideoActionsToast

/// Confirms a video saved from its context menu ("Added to Watch Later"), or
/// reports that saving failed, over the YouTube pages.
struct YouTubeVideoActionsToast: View {
    private let actions = YouTubeVideoActions.shared

    private static let duration: Duration = .seconds(3)

    var body: some View {
        Group {
            if let toast = self.actions.toast {
                ToastView(message: toast.message, isError: toast.isError) {
                    self.actions.clearToast(id: toast.id)
                }
                .frame(maxWidth: 420)
                .task(id: toast.id) {
                    try? await Task.sleep(for: Self.duration)
                    guard !Task.isCancelled else { return }
                    self.actions.clearToast(id: toast.id)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier(AccessibilityID.YouTubeContent.videoActionsToast)
            }
        }
        .padding(.top, 12)
        .animation(.spring(duration: 0.3), value: self.actions.toast?.id)
    }
}

// MARK: - AccessibilityID Additions

extension AccessibilityID.YouTubeContent {
    static let videoActionsToast = "youtubeContent.videoActionsToast"
}
