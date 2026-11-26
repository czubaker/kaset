import SwiftUI

// MARK: - MusicToolbarItem

/// A YouTube Music player bar item placed in the window toolbar, drawn as an
/// ordinary toolbar button. The toolbar's own items (Command Bar, Customize)
/// and spaces are the main window's.
struct MusicToolbarItem: View {
    let item: MusicPlayerBarItem

    @Environment(PlayerService.self) private var playerService
    @Environment(AuthService.self) private var authService
    @State private var airPlayAnchor = AirPlayPickerAnchor()

    /// Whether the item draws anything right now.
    static func isShown(_ item: MusicPlayerBarItem, hasPersonalAccount: Bool) -> Bool {
        switch item {
        case .like, .dislike: hasPersonalAccount
        case .artwork, .songInfo, .mixTracks, .commandBar, .customize, .space, .flexibleSpace: false
        default: true
        }
    }

    var body: some View {
        self.content
            .environment(\.playerBarItemStyle, .toolbar)
    }

    @ViewBuilder
    private var content: some View {
        let player = self.playerService
        let hasTrack = player.currentTrack != nil
        switch self.item {
        case .like:
            ToolbarButton(
                title: String(localized: "Like"),
                systemImage: player.currentTrackLikeStatus == .like ? "hand.thumbsup.fill" : "hand.thumbsup",
                isSelected: player.currentTrackLikeStatus == .like
            ) { player.likeCurrentTrack() }
                .disabled(!hasTrack)
        case .dislike:
            ToolbarButton(
                title: String(localized: "Dislike"),
                systemImage: player.currentTrackLikeStatus == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                isSelected: player.currentTrackLikeStatus == .dislike
            ) { player.dislikeCurrentTrack() }
                .disabled(!hasTrack)
        case .airPlay:
            ToolbarButton(title: String(localized: "AirPlay"), systemImage: "airplayaudio", isSelected: player.isAirPlayConnected) {
                player.showAirPlayPicker(at: self.airPlayAnchor.screenPoint)
            }
            .background {
                AirPlayPickerAnchorView(anchor: self.airPlayAnchor)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .disabled(!hasTrack)
        case .shuffle:
            ToolbarButton(title: String(localized: "Shuffle"), systemImage: "shuffle", isSelected: player.shuffleEnabled) {
                player.cycleShuffleMode()
            }
            .disabled(!hasTrack)
        case .previous:
            ToolbarButton(title: String(localized: "Previous track"), systemImage: "backward.fill") {
                Task { await player.previous() }
            }
            .disabled(!hasTrack)
        case .playPause:
            ToolbarButton(
                title: player.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                systemImage: player.isPlaying ? "pause.fill" : "play.fill"
            ) { Task { await player.playPause() } }
                .disabled(!hasTrack)
        case .next:
            ToolbarButton(title: String(localized: "Next track"), systemImage: "forward.fill") {
                Task { await player.next() }
            }
            .disabled(!hasTrack)
        case .repeatMode:
            ToolbarButton(
                title: String(localized: "Repeat"),
                systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                isSelected: player.repeatMode != .off
            ) { player.cycleRepeatMode() }
                .disabled(!hasTrack)
        case .volume:
            ToolbarVolumeButton(volume: player.volume) { player.setVolumeImmediately($0) }
        case .lyrics:
            ToolbarButton(title: String(localized: "Lyrics"), systemImage: "quote.bubble", isSelected: player.showLyrics) {
                withAnimation(AppAnimation.standard) { player.showLyrics.toggle() }
            }
        case .queue:
            ToolbarButton(title: String(localized: "Queue"), systemImage: "list.bullet", isSelected: player.showQueue) {
                withAnimation(AppAnimation.standard) { player.showQueue.toggle() }
            }
        case .video:
            ToolbarButton(
                title: String(localized: "Video"),
                systemImage: player.showVideo ? "pip.exit" : "pip.enter",
                isSelected: player.showVideo
            ) {
                withAnimation(AppAnimation.standard) { player.showVideo.toggle() }
            }
            .disabled(!self.canShowVideo)
        case .miniPlayer:
            ToolbarButton(
                title: player.isMiniPlayerVisible ? String(localized: "Return to Kaset") : String(localized: "Switch to Mini Player"),
                systemImage: player.isMiniPlayerVisible ? "macwindow" : "rectangle.inset.bottomright.filled",
                isSelected: player.isMiniPlayerVisible
            ) { _ = player.toggleMiniPlayer(mode: .switchFromMainWindow) }
        case .sleepTimer:
            SleepTimerBarButton()
        case .artwork, .songInfo, .mixTracks, .commandBar, .customize, .space, .flexibleSpace:
            EmptyView()
        }
    }

    private var canShowVideo: Bool {
        guard let track = self.playerService.currentTrack else { return false }
        return self.playerService.currentTrackHasVideo || track.musicVideoType?.hasVideoContent == true
    }
}
