import SwiftUI

// MARK: - YouTubePlayerBarTimelineLane

/// The YouTube player bar's seek lane. This is the only YouTube player bar view that
/// observes `YouTubePlayerService.progress`, so each playback tick re-evaluates just this
/// lane instead of the whole bar. Nothing outside the lane reads its seek state, so the
/// state lives here and is discarded when an ad replaces the lane.
struct YouTubePlayerBarTimelineLane: View {
    let accent: Color
    let markers: [PlayerBarProgressMarker]
    let segments: [PlayerBarProgressSegment]
    let isLive: Bool
    let canSeek: Bool
    let onMarkerPreviewChange: (PlayerBarProgressMarker?) -> Void

    @Environment(YouTubePlayerService.self) private var youtubePlayer

    @State private var seekValue: Double = 0
    @State private var isSeeking = false
    @State private var seekHold = PlayerBarSeekHold()
    /// The 0…1 position under the pointer on the bar, for the frame preview.
    @State private var hoverFraction: Double?

    var body: some View {
        PlayerBarProgressLane(
            fraction: self.displayFraction,
            accent: self.accent,
            elapsedText: PlayerBarSeekController.formatTime(self.progressTextValue),
            remainingText: "-\(PlayerBarSeekController.formatTime(max(0, self.youtubePlayer.duration - self.progressTextValue)))",
            markers: self.markers,
            segments: self.segments,
            heatmap: self.isLive ? [] : self.youtubePlayer.heatmap,
            liveEdge: self.liveEdge,
            isLive: self.isLive,
            canSeek: self.canSeek,
            isLoading: self.youtubePlayer.isPlaybackLoading,
            onScrub: { fraction in
                self.isSeeking = true
                self.seekValue = fraction
            },
            onCommit: self.performSeek,
            onMarkerPreviewChange: self.onMarkerPreviewChange,
            onHoverFractionChange: { self.hoverFraction = $0 }
        )
        .overlay(alignment: .topLeading) {
            self.framePreview
        }
        .onChange(of: self.youtubePlayer.progress) { _, newValue in
            self.reconcileHold(observedProgress: newValue)
            if !self.isSeeking, !self.seekHold.isActive, self.youtubePlayer.duration > 0 {
                self.seekValue = self.displayedPlaybackProgress / self.youtubePlayer.duration
            }
        }
        .onChange(of: self.youtubePlayer.duration) { _, newValue in
            self.reconcileHold(observedProgress: self.youtubePlayer.progress)
            if !self.isSeeking, !self.seekHold.isActive, newValue > 0 {
                self.seekValue = self.displayedPlaybackProgress / newValue
            }
        }
        .onChange(of: self.currentSeekIdentity) { _, _ in
            self.clearSeekHold()
        }
        .onChange(of: self.canSeek) { _, _ in
            self.clearSeekHold()
        }
        .onAppear {
            self.syncSeekValueFromDisplayedProgress()
        }
    }

    /// The storyboard frame under the pointer, floating above the bar (and
    /// its "most replayed" curve), held inside the bar's ends.
    @ViewBuilder
    private var framePreview: some View {
        if let hoverFraction = self.hoverFraction, !self.isLive, self.youtubePlayer.duration > 0,
           let spec = self.youtubePlayer.storyboardSpec
        {
            GeometryReader { proxy in
                let halfWidth = StoryboardHoverPreview.previewWidth / 2
                StoryboardHoverPreview(spec: spec, fraction: hoverFraction, duration: self.youtubePlayer.duration)
                    .position(
                        x: min(max(halfWidth, proxy.size.width * hoverFraction), max(halfWidth, proxy.size.width - halfWidth)),
                        y: -StoryboardHoverPreview.totalHeight / 2 - PlayerBarHeatmap.height + 12
                    )
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// How far behind the live head still counts as live: the page reports
    /// the window's end a little ahead of what has buffered.
    static let liveEdgeTolerance: TimeInterval = 10

    /// For a live stream that can be rewound: LIVE, and a jump to the
    /// broadcast's head.
    private var liveEdge: PlayerBarLiveEdge? {
        let player = self.youtubePlayer
        guard player.isLiveSeekable, player.duration > 0 else { return nil }
        let behind = player.duration - self.displayedPlaybackProgress
        return PlayerBarLiveEdge(isAtEdge: behind <= Self.liveEdgeTolerance) {
            player.seek(to: player.duration)
        }
    }

    /// Fraction (0...1) to render: the live drag value while seeking, otherwise actual progress.
    private var displayFraction: Double {
        if self.isSeeking {
            return min(max(0, self.seekValue), 1)
        }
        guard self.youtubePlayer.duration > 0 else { return 0 }
        return min(max(0, self.displayedPlaybackProgress / self.youtubePlayer.duration), 1)
    }

    private var progressTextValue: TimeInterval {
        self.isSeeking ? self.seekValue * self.youtubePlayer.duration : self.displayedPlaybackProgress
    }

    private var displayedPlaybackProgress: TimeInterval {
        self.seekHold.displayProgress(observedProgress: self.youtubePlayer.progress)
    }

    private var currentSeekIdentity: String {
        self.youtubePlayer.currentVideo?.videoId ?? "none"
    }

    private func performSeek() {
        guard self.isSeeking, self.canSeek else { return }
        let seekTime = self.seekValue * self.youtubePlayer.duration
        let holdID = self.seekHold.begin(target: seekTime)
        self.isSeeking = false
        self.youtubePlayer.seek(to: seekTime)

        Task { @MainActor in
            try? await Task.sleep(for: PlayerBarSeekHold.timeout)
            if self.seekHold.clearIfCurrent(holdID) {
                self.syncSeekValueFromDisplayedProgress()
            }
        }
    }

    /// Writes the hold back only when reconciling changes it, so idle ticks don't invalidate the lane twice.
    private func reconcileHold(observedProgress: TimeInterval) {
        var hold = self.seekHold
        hold.reconcile(observedProgress: observedProgress)
        if hold != self.seekHold {
            self.seekHold = hold
        }
    }

    private func clearSeekHold() {
        self.seekHold.clear()
        self.isSeeking = false
        self.syncSeekValueFromDisplayedProgress()
    }

    private func syncSeekValueFromDisplayedProgress() {
        if self.youtubePlayer.duration > 0 {
            self.seekValue = self.displayedPlaybackProgress / self.youtubePlayer.duration
        } else {
            self.seekValue = 0
        }
    }
}
