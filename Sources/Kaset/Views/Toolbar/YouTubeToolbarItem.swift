import SwiftUI

// MARK: - YouTubeToolbarItem

/// A YouTube player bar item placed in the window toolbar, drawn as an
/// ordinary toolbar button. The toolbar's own items (Refresh, Notifications,
/// Zoom, the Customize buttons) and spaces are the main window's.
struct YouTubeToolbarItem: View {
    let item: YouTubePlayerBarItem

    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @State private var airPlayAnchor = AirPlayPickerAnchor()
    @State private var settings = SettingsManager.shared

    /// Whether the item draws anything right now.
    static func isShown(_ item: YouTubePlayerBarItem, player: YouTubePlayerService, hasPersonalAccount: Bool) -> Bool {
        let isUnseekableLive = player.currentVideo?.isLive == true && !player.isLiveSeekable
        switch item {
        case .like, .dislike, .watchLater, .saveToPlaylist:
            return hasPersonalAccount
        case .subscribeIcon:
            return hasPersonalAccount && Self.channelId(of: player) != nil
        case .skipBack, .skipForward, .skipBack5, .skipForward5, .skipBack10, .skipForward10,
             .skipBack15, .skipForward15, .skipBack60, .skipForward60:
            return !isUnseekableLive
        case .captions, .quality, .playbackSpeed, .audioTrack:
            return YouTubePlayerBarMenu.isShown(item, player: player)
        case .thumbnail, .channelAvatar, .videoInfo, .channelInfo, .subscribe, .floatOnTop,
             .refresh, .notifications, .zoom, .customizeWatchPage, .customize, .space, .flexibleSpace:
            return false
        default:
            return true
        }
    }

    static func channelId(of player: YouTubePlayerService) -> String? {
        if let channelId = player.currentVideo?.channelId, !channelId.isEmpty {
            return channelId
        }
        guard let channelId = player.currentChannel?.channelId, !channelId.isEmpty else { return nil }
        return channelId
    }

    var body: some View {
        self.content
            .environment(\.playerBarItemStyle, .toolbar)
    }

    @ViewBuilder
    private var content: some View {
        let player = self.youtubePlayer
        let hasVideo = player.currentVideo != nil
        switch self.item {
        case .subscribeIcon:
            if let channelId = Self.channelId(of: player) {
                YouTubePlayerBarSubscribeButton(channelId: channelId, client: player.youtubeClient, isCompact: true)
            }
        case .like:
            ToolbarButton(
                title: String(localized: "Like"),
                systemImage: player.currentRating == .like ? "hand.thumbsup.fill" : "hand.thumbsup",
                isSelected: player.currentRating == .like
            ) { Task { await player.toggleLike() } }
                .disabled(!hasVideo)
        case .dislike:
            ToolbarButton(
                title: String(localized: "Dislike"),
                systemImage: player.currentRating == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                isSelected: player.currentRating == .dislike
            ) { Task { await player.toggleDislike() } }
                .disabled(!hasVideo)
        case .skipBack, .skipForward, .skipBack5, .skipForward5, .skipBack10, .skipForward10,
             .skipBack15, .skipForward15, .skipBack60, .skipForward60:
            if let seek = self.item.seek {
                YouTubePlayerBarSeekButton(seconds: seek.seconds, isForward: seek.isForward, canSeek: self.canSeek)
            }
        case .previousVideo, .nextVideo:
            YouTubePlayerBarVideoSkipButton(isForward: self.item == .nextVideo)
        case .playPause:
            ToolbarButton(
                title: player.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                systemImage: player.isPlaying ? "pause.fill" : "play.fill"
            ) { player.playPause() }
                .disabled(!hasVideo)
        case .volume:
            ToolbarVolumeButton(volume: player.volume) { player.volume = $0 }
        case .fullView:
            ToolbarButton(title: String(localized: "Full view"), systemImage: "arrow.up.left.and.arrow.down.right") {
                self.openFullView()
            }
            .disabled(!hasVideo)
        case .watchLater:
            ToolbarButton(
                title: String(localized: "Add to Watch Later"),
                systemImage: player.isInWatchLater ? "clock.fill" : "clock",
                isSelected: player.isInWatchLater
            ) { Task { await player.toggleWatchLater() } }
                .disabled(!hasVideo)
        case .saveToPlaylist:
            YouTubePlayerBarPlaylistMenu()
        case .share:
            YouTubePlayerBarShareButton()
        case .airPlay:
            ToolbarButton(title: String(localized: "AirPlay"), systemImage: "airplayvideo") {
                player.showAirPlayPicker(at: self.airPlayAnchor.screenPoint)
            }
            .background {
                AirPlayPickerAnchorView(anchor: self.airPlayAnchor)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .disabled(!hasVideo)
        case .captions, .quality, .playbackSpeed, .audioTrack:
            YouTubePlayerBarMenu(item: self.item)
        case .settingsMenu:
            YouTubeVideoSettingsMenu(items: self.settings.youtubePlayerBar.items(in: .settingsMenu))
        case .pictureInPicture:
            ToolbarButton(
                title: player.surfaceLocation == .floating
                    ? String(localized: "Pop video back into Kaset")
                    : String(localized: "Picture in Picture"),
                systemImage: player.surfaceLocation == .floating ? "pip.exit" : "pip.enter",
                isSelected: player.surfaceLocation == .floating
            ) { self.togglePictureInPicture() }
                .disabled(!hasVideo || player.isWindowFullscreen)
        case .queue:
            YouTubePlayerBarQueueButton()
        case .sleepTimer:
            SleepTimerBarButton()
        case .thumbnail, .channelAvatar, .videoInfo, .channelInfo, .subscribe, .floatOnTop,
             .refresh, .notifications, .zoom, .customizeWatchPage, .customize, .space, .flexibleSpace:
            EmptyView()
        }
    }

    private var canSeek: Bool {
        let player = self.youtubePlayer
        let isLive = player.currentVideo?.isLive == true
        return player.duration > 0 && !player.isShowingAd && (!isLive || player.isLiveSeekable)
    }

    /// As the bar's Full View: pops the video out and makes it full screen.
    private func openFullView() {
        if self.youtubePlayer.surfaceLocation == .inline {
            self.youtubePlayer.popOutToWindow()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                YouTubeVideoWindowController.shared.toggleFullscreen(returnInlineOnExit: true)
            }
        } else {
            YouTubeVideoWindowController.shared.toggleFullscreen()
        }
    }

    private func togglePictureInPicture() {
        guard !self.youtubePlayer.isWindowFullscreen else { return }
        if self.youtubePlayer.surfaceLocation == .floating {
            self.youtubePlayer.requestPopIn()
        } else {
            self.youtubePlayer.popOutToWindow()
        }
    }
}
