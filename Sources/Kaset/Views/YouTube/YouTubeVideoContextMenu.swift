import AppKit
import SwiftUI

// MARK: - YouTubeVideoContextMenu

/// A video card's context menu, in line with the overflow menu on youtube.com:
/// Play Next and Add to Queue for videos (not Shorts), Add to Watch Later and
/// Add to Playlist when signed in, then the card's
/// "Not interested" / "Don't recommend channel" entries where the page
/// handles them. A card with nothing to offer gets no menu.
struct YouTubeVideoContextMenu: ViewModifier {
    let video: YouTubeVideo
    /// Sends a recommendation-feedback action; nil where the page can't.
    let sendFeedback: ((YouTubeFeedbackAction) -> Void)?
    /// Takes the video off the playlist page it's on, where the user can edit it.
    let removal: YouTubeVideoRemoval?

    @Environment(AuthService.self) private var authService
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    func body(content: Content) -> some View {
        let canSave = self.authService.hasPersonalAccount
        let feedbackActions = self.sendFeedback == nil ? [] : self.video.feedbackActions
        content.contextMenu {
            if !self.video.isShort {
                Button {
                    self.queue(next: true)
                } label: {
                    Label(String(localized: "Play Next"), systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button {
                    self.queue(next: false)
                } label: {
                    Label(String(localized: "Add to Queue"), systemImage: "text.append")
                }
                Divider()
            }

            if canSave {
                Button {
                    Task { await YouTubeVideoActions.shared.saveToWatchLater(self.video) }
                } label: {
                    Label(String(localized: "Add to Watch Later"), systemImage: "clock")
                }
                YouTubeAddToPlaylistMenu(video: self.video)
            }

            if let removal = self.removal {
                Divider()
                Button(role: .destructive, action: removal.action) {
                    Label(removal.title, systemImage: "minus.circle")
                }
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

            if let url = self.video.shareURL {
                Divider()
                Button {
                    ShareContextMenu.showSharePicker(for: url)
                } label: {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                }
                Button {
                    CopyLinkSharingPickerDelegate.copy(url, to: .general)
                } label: {
                    Label(String(localized: "Copy Link"), systemImage: "link")
                }
                // YouTube's report form needs the signed-in web session, which
                // Kaset's API client doesn't hold, so reports go through the site.
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(String(localized: "Report on YouTube…"), systemImage: "flag")
                }
            }
        }
    }
}

private extension YouTubeVideoContextMenu {
    /// Queues the video, or plays it when nothing plays yet.
    func queue(next: Bool) {
        guard self.youtubePlayer.currentVideo != nil else {
            YouTubePageRefresh.shared.store?.navigationPath.append(.watch(self.video))
            return
        }
        if next {
            self.youtubePlayer.playNext(self.video)
        } else {
            self.youtubePlayer.addToQueue(self.video)
        }
        HapticService.toggle()
    }
}

// MARK: - YouTubeVideoRemoval

/// A context menu entry that takes a video off the playlist page it's on.
struct YouTubeVideoRemoval {
    let title: String
    let action: () -> Void
}

extension View {
    /// Attaches the video context menu for `video`. Pass `sendFeedback` on
    /// pages that can drop a card after "Not interested" / "Don't recommend
    /// channel", and `removal` on playlist pages the user can edit.
    func youtubeVideoContextMenu(
        for video: YouTubeVideo,
        removal: YouTubeVideoRemoval? = nil,
        sendFeedback: ((YouTubeFeedbackAction) -> Void)? = nil
    ) -> some View {
        self.modifier(YouTubeVideoContextMenu(video: video, sendFeedback: sendFeedback, removal: removal))
    }
}

// MARK: - YouTubeAddToPlaylistMenu

/// The user's playlists, loaded each time the context menu opens. Playlists
/// that hold the video are checked; picking one removes the video from it.
private struct YouTubeAddToPlaylistMenu: View {
    let video: YouTubeVideo

    @State private var membership = YouTubePlaylistMembership()

    var body: some View {
        Menu {
            YouTubePlaylistMembershipItems(video: self.video, membership: self.membership)
        } label: {
            Label(String(localized: "Add to Playlist"), systemImage: "text.badge.plus")
        }
        // Load as the context menu is built, not when the submenu opens: menus
        // are largely snapshotted while open, so a late load would leave
        // "Loading Playlists…" until the menu is reopened.
        .task {
            await self.membership.load(for: self.video)
        }
    }
}

// MARK: - YouTubePlaylistMembershipItems

/// Menu items for the user's playlists: each toggles whether it holds the
/// video, with a checkmark on the ones that do.
struct YouTubePlaylistMembershipItems: View {
    let video: YouTubeVideo
    let membership: YouTubePlaylistMembership

    var body: some View {
        if let options = self.membership.options {
            if options.isEmpty {
                Label(String(localized: "No Playlists"), systemImage: "list.and.film")
            } else {
                ForEach(options) { option in
                    Button {
                        Task { await self.membership.toggle(option, for: self.video) }
                    } label: {
                        Label(option.title, systemImage: option.isSelected ? "checkmark.circle.fill" : "list.and.film")
                    }
                }
            }
        } else if self.membership.didFail {
            Button {
                Task { await self.membership.load(for: self.video) }
            } label: {
                Label(String(localized: "Retry Loading Playlists"), systemImage: "arrow.clockwise")
            }
        } else {
            Label(String(localized: "Loading Playlists…"), systemImage: "hourglass")
        }
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
