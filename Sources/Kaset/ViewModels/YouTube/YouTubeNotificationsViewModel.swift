import Foundation
import Observation

// MARK: - YouTubeNotificationsViewModel

/// YouTube's notification inbox for the toolbar's bell. Opening the inbox
/// marks what it lists as seen on this Mac, so only later arrivals light the
/// badge; nothing is marked read on YouTube. Ported from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
@MainActor
@Observable
final class YouTubeNotificationsViewModel {
    private(set) var notifications: [YouTubeNotification] = []
    /// What was new when the inbox was last opened, to mark in the list.
    private(set) var newlyOpenedIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var didFail = false

    /// Unread on YouTube and not yet seen here.
    var unseenCount: Int {
        self.notifications.count { !$0.isRead && !self.seenIDs.contains($0.id) }
    }

    /// Changes when the account does, so the bell's poll restarts for it.
    let pollID = UUID()

    /// Newest first.
    private var seenOrder: [String]
    private var seenIDs: Set<String>
    private let client: any YouTubeClientProtocol
    private let defaults: UserDefaults
    private let logger = DiagnosticsLogger.api

    static let seenKey = "youtube.notifications.seenIDs"
    /// How many seen IDs are remembered, newest first. One list serves every
    /// account (IDs don't repeat across accounts), so it is capped rather
    /// than pruned to the inbox on screen.
    static let maximumSeenIDs = 500
    /// How often the badge checks for new notifications.
    static let pollInterval: Duration = .seconds(180)

    init(client: any YouTubeClientProtocol, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        let seenOrder = defaults.stringArray(forKey: Self.seenKey) ?? []
        self.seenOrder = seenOrder
        self.seenIDs = Set(seenOrder)
    }

    /// Refreshes the inbox until the calling task is cancelled.
    func poll() async {
        while !Task.isCancelled {
            await self.refresh(markingSeen: false)
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    /// Refreshes the inbox as it opens and marks what it lists as seen.
    func open() async {
        self.isLoading = true
        defer { self.isLoading = false }
        await self.refresh(markingSeen: true)
    }

    func isNew(_ notification: YouTubeNotification) -> Bool {
        self.newlyOpenedIDs.contains(notification.id)
    }

    private func refresh(markingSeen: Bool) async {
        do {
            let notifications = try await self.client.getNotifications()
            self.notifications = notifications
            self.didFail = false

            guard markingSeen else { return }
            self.newlyOpenedIDs = Set(notifications.filter { !$0.isRead && !self.seenIDs.contains($0.id) }.map(\.id))
            let listed = notifications.map(\.id)
            guard !Set(listed).isSubset(of: self.seenIDs) else { return }
            let listedSet = Set(listed)
            self.seenOrder = Array((listed + self.seenOrder.filter { !listedSet.contains($0) }).prefix(Self.maximumSeenIDs))
            self.seenIDs = Set(self.seenOrder)
            self.defaults.set(self.seenOrder, forKey: Self.seenKey)
        } catch {
            guard !(error is CancellationError) else { return }
            self.didFail = true
            self.logger.error("Failed to load YouTube notifications: \(error.localizedDescription)")
        }
    }
}
