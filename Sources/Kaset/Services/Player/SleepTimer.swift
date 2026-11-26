import Foundation
import Observation

// MARK: - SleepTimer

/// Pauses whatever is playing, music or video, after a while or when the
/// current track or video ends. Nothing persists: quitting turns it off.
@MainActor
@Observable
final class SleepTimer {
    static let shared = SleepTimer()

    enum Setting: Equatable {
        case minutes(Int)
        /// When the track or video playing now ends.
        case endOfItem
    }

    /// What's playing, as the timer needs to know it.
    struct NowPlaying: Equatable {
        let id: String
        let progress: TimeInterval
        let duration: TimeInterval
        let isPlaying: Bool
        /// A video rather than a track, for the menus' wording.
        let isVideo: Bool
        /// An ad plays, whose timeline isn't the item's.
        var isAd = false
    }

    /// The choices menus offer, in minutes.
    static let presets = [15, 30, 45, 60, 90, 120]

    private(set) var setting: Setting?
    /// When a timed setting pauses.
    private(set) var deadline: Date?
    /// Seconds left of a timed setting, updated every second.
    private(set) var remaining: TimeInterval?

    var isActive: Bool {
        self.setting != nil
    }

    /// Pauses every player that plays. Set by the app.
    @ObservationIgnored var pausePlayback: (() -> Void)?
    /// What the routed player plays. Set by the app.
    @ObservationIgnored var nowPlaying: (() -> NowPlaying?)?

    /// The item playing when End of Track started, to notice it ended
    /// even when the next one starts at once.
    private var itemID: String?
    /// The item ended but what follows hasn't started yet; pause it once it
    /// does.
    private var isWaitingForNextItem = false
    /// Seconds the item had left at the last look, to tell an item that ran
    /// out from one the user skipped.
    private var lastRemaining: TimeInterval?
    private var task: Task<Void, Never>?

    func start(_ setting: Setting, now: Date = Date()) {
        self.setting = setting
        self.itemID = self.nowPlaying?()?.id
        self.isWaitingForNextItem = false
        self.lastRemaining = nil
        switch setting {
        case let .minutes(minutes):
            let deadline = now.addingTimeInterval(TimeInterval(minutes * 60))
            self.deadline = deadline
            self.remaining = deadline.timeIntervalSince(now)
        case .endOfItem:
            self.deadline = nil
            self.remaining = nil
        }
        self.task?.cancel()
        self.task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    func cancel() {
        self.task?.cancel()
        self.task = nil
        self.setting = nil
        self.deadline = nil
        self.remaining = nil
        self.itemID = nil
        self.isWaitingForNextItem = false
        self.lastRemaining = nil
    }

    /// Checks whether it's time to pause; internal so tests can drive it.
    func tick(now: Date = Date()) {
        switch self.setting {
        case nil:
            return
        case .minutes:
            guard let deadline = self.deadline else { return }
            let left = deadline.timeIntervalSince(now)
            if left <= 0 {
                self.fire()
            } else {
                self.remaining = left.rounded(.up)
            }
        case .endOfItem:
            self.tickEndOfItem()
        }
    }

    private func tickEndOfItem() {
        guard let playing = self.nowPlaying?() else { return }
        guard let itemID = self.itemID else {
            // Started with nothing playing: wait for the next item's end.
            self.itemID = playing.id
            return
        }
        if self.isWaitingForNextItem {
            // The next item may still be loading: a pause before it plays
            // would find nothing playing.
            if playing.isPlaying {
                self.fire()
            }
            return
        }
        if playing.id != itemID {
            // Ran out (it had seconds left at the last look) and the next
            // one followed: pause that. Otherwise the user moved on, so wait
            // for the end of what they picked.
            if let lastRemaining = self.lastRemaining, lastRemaining <= 5 {
                self.isWaitingForNextItem = true
                if playing.isPlaying {
                    self.fire()
                }
            } else {
                self.itemID = playing.id
                self.lastRemaining = nil
            }
            return
        }
        guard !playing.isAd, playing.duration > 0 else { return }
        let remaining = playing.duration - playing.progress
        if remaining <= 1.2 {
            if playing.isPlaying {
                self.fire()
            } else {
                // Played to its end with nothing after it: nothing to pause.
                self.cancel()
            }
            return
        }
        self.lastRemaining = remaining
    }

    private func fire() {
        self.pausePlayback?()
        self.cancel()
    }

    /// "12:34" or "1:02:03" left.
    static func formatted(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// A preset's name: "15 minutes", "1 hour", "1 hour, 30 minutes".
    static func title(forMinutes minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
