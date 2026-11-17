import Foundation
import Observation

// MARK: - YouTubeChannelSubscriptions

/// Whether the account is subscribed to a channel, shared by everything that
/// shows a Subscribe button for it: the watch page and the player bar. A tap
/// on either shows on both.
@MainActor
@Observable
final class YouTubeChannelSubscriptions {
    static let shared = YouTubeChannelSubscriptions()

    /// Known states by channel ID: from watch pages, then from the user's taps.
    private(set) var states: [String: Bool] = [:]

    /// Channels with a change in flight, so a second tap waits for the first.
    private var pending: Set<String> = []

    /// Bumped by `reset()`, so a change that finishes after an account switch
    /// doesn't write into the new account's states.
    private var generation = 0

    private let logger = DiagnosticsLogger.api

    func isSubscribed(to channelId: String) -> Bool? {
        self.states[channelId]
    }

    /// Records what a watch page loaded. A change in flight keeps its
    /// optimistic state instead.
    func seed(_ isSubscribed: Bool, channelId: String) {
        guard !self.pending.contains(channelId) else { return }
        self.states[channelId] = isSubscribed
    }

    /// Subscribes or unsubscribes, showing the new state at once and rolling
    /// it back if YouTube refuses. Returns whether the change went through.
    @discardableResult
    func setSubscribed(_ subscribed: Bool, channelId: String, client: any YouTubeClientProtocol) async -> Bool {
        guard !self.pending.contains(channelId) else { return false }
        let generation = self.generation
        let previous = self.states[channelId]
        self.pending.insert(channelId)
        self.states[channelId] = subscribed
        do {
            try await client.setSubscribed(subscribed, channelId: channelId)
            guard generation == self.generation else { return false }
            self.pending.remove(channelId)
            HapticService.toggle()
            return true
        } catch {
            guard generation == self.generation else { return false }
            self.pending.remove(channelId)
            self.logger.error("Failed to change subscription: \(error.localizedDescription)")
            self.states[channelId] = previous
            return false
        }
    }

    /// Forgets every state, after the account changes.
    func reset() {
        self.generation += 1
        self.states = [:]
        self.pending = []
    }
}
