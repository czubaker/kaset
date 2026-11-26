import Foundation

// MARK: - Autoplay

/// With Autoplay on, a video that plays to its end counts down to the next
/// related video behind a card over the video, then plays it; the card can
/// play it now or cancel. Anything the user plays, stops, or skips to clears
/// the countdown. Ported from KasetPlus (github.com/Yoddikko/kasetPlus, MIT).
extension YouTubePlayerService {
    /// How long the "Up Next" card counts down.
    static let autoplayCountdownSeconds = 5

    /// Queues the next video after a natural finish: the first related video
    /// the watch page loaded, or one fetched now (a pop-out finish).
    func startAutoplayIfEnabled() {
        guard SettingsManager.shared.youtubeAutoplayEnabled, let current = self.currentVideo else { return }
        if let next = self.upNext.first(where: { !$0.isShort }) {
            self.startAutoplayCountdown(to: next)
            return
        }
        let videoId = current.videoId
        Task { @MainActor in
            guard let client = self.youtubeClient,
                  let next = try? await client.getWatchNext(videoId: videoId).related.first(where: { !$0.isShort }),
                  SettingsManager.shared.youtubeAutoplayEnabled,
                  self.currentVideo?.videoId == videoId,
                  !self.isPlaying,
                  self.autoplayPendingVideo == nil
            else { return }
            self.startAutoplayCountdown(to: next)
        }
    }

    func startAutoplayCountdown(to next: YouTubeVideo) {
        self.autoplayCountdownTask?.cancel()
        self.autoplayPendingVideo = next
        self.autoplayCountdownRemaining = Self.autoplayCountdownSeconds
        self.autoplayCountdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.autoplayPendingVideo?.videoId == next.videoId else { return }
                self.autoplayCountdownRemaining -= 1
                if self.autoplayCountdownRemaining <= 0 {
                    self.confirmAutoplayNow()
                    return
                }
            }
        }
    }

    /// Plays the queued video now (the card's countdown button).
    func confirmAutoplayNow() {
        guard let next = self.autoplayPendingVideo else { return }
        self.clearAutoplayCountdown()
        self.advance(to: next)
    }

    /// Dismisses the card without playing anything.
    func cancelAutoplay() {
        self.clearAutoplayCountdown()
    }

    func clearAutoplayCountdown() {
        self.autoplayCountdownTask?.cancel()
        self.autoplayCountdownTask = nil
        if self.autoplayPendingVideo != nil {
            self.autoplayPendingVideo = nil
        }
        self.autoplayCountdownRemaining = 0
    }
}
