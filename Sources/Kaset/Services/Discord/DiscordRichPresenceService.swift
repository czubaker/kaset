import Foundation

// MARK: - DiscordRichPresenceService

/// Publishes what Kaset is playing to the local Discord client. Off until the
/// user turns it on in Settings → Scrobbling. Ported from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
///
/// Polls rather than observing the players: Discord rate-limits presence
/// updates to roughly 5 per 20 seconds, so a low-frequency poll that only
/// transmits on change is both simpler and a better fit than reacting to every
/// 1 Hz playback tick. Nothing in the playback path needs to know we exist.
@MainActor
@Observable
final class DiscordRichPresenceService {
    static let shared = DiscordRichPresenceService()

    /// How the connection is doing, surfaced in Settings so a failure is
    /// visible instead of the presence just never appearing.
    enum Status: Equatable {
        case disabled
        case waitingForDiscord
        case connected
        case rejected(String)
        case failed(String)
    }

    private(set) var status: Status = .disabled

    private let client = DiscordIPCClient()
    private let logger = DiagnosticsLogger.player
    private var pollTask: Task<Void, Never>?
    private var lastSnapshot: DiscordPresenceSnapshot?
    private var isConnected = false
    /// The Application ID the running loop is using, so editing the field
    /// reconnects instead of silently keeping the old identity.
    private var activeApplicationID: String?

    private weak var playerService: PlayerService?
    private weak var youtubePlayerService: YouTubePlayerService?

    /// Poll interval. Comfortably under Discord's limit, and slow enough that
    /// the loop costs nothing while music plays for an hour.
    private static let pollInterval: Duration = .seconds(5)
    /// Backoff when Discord is not running, so we are not stat-ing ten socket
    /// paths every five seconds all day.
    private static let idleRetryInterval: Duration = .seconds(30)
    /// Reconnecting after Discord dropped us (a restart, an update) waits only
    /// this long.
    private static let reconnectInterval: Duration = .seconds(2)
    /// A pause shorter than this keeps the presence (as paused); a longer
    /// one clears it, so a stopped player doesn't stay on the profile.
    nonisolated static let pausedGrace: TimeInterval = 30
    /// When the presented snapshot was first seen paused.
    private var pausedSince: Date?

    private init() {}

    func configure(playerService: PlayerService, youtubePlayerService: YouTubePlayerService) {
        self.playerService = playerService
        self.youtubePlayerService = youtubePlayerService
        self.refreshEnablement()
    }

    /// Starts or stops the loop to match the current settings.
    func refreshEnablement() {
        let settings = SettingsManager.shared
        guard settings.discordRichPresenceEnabled else {
            self.stop(status: .disabled)
            return
        }
        // A build whose application ID constant is broken simply stays off; the
        // suite pins that constant so it cannot ship that way.
        let applicationID = DiscordPresenceActivity.defaultApplicationID
        guard DiscordPresenceActivity.isValidApplicationID(applicationID) else {
            self.stop(status: .disabled)
            return
        }
        if self.pollTask != nil {
            guard self.activeApplicationID != applicationID else { return }
            self.stop(status: .waitingForDiscord)
        }
        self.activeApplicationID = applicationID
        self.status = .waitingForDiscord
        self.pollTask = Task { [weak self] in
            await self?.run()
        }
    }

    private func stop(status: Status) {
        self.pollTask?.cancel()
        self.pollTask = nil
        self.lastSnapshot = nil
        self.activeApplicationID = nil
        self.status = status
        let client = self.client
        self.isConnected = false
        Task { await client.disconnect() }
    }

    // MARK: - Loop

    private func run() async {
        while !Task.isCancelled {
            let interval = await self.tick()
            try? await Task.sleep(for: interval)
        }
    }

    /// One poll. Returns how long to wait before the next one.
    private func tick() async -> Duration {
        let applicationID = self.activeApplicationID ?? DiscordPresenceActivity.defaultApplicationID

        if !self.isConnected {
            do {
                try await self.client.connect(applicationID: applicationID)
                self.isConnected = true
                self.status = .connected
                self.lastSnapshot = nil
            } catch DiscordIPCError.discordNotRunning {
                self.status = .waitingForDiscord
                return Self.idleRetryInterval
            } catch let DiscordIPCError.rejected(code, message) {
                // A wrong Application ID fails identically forever; stop rather
                // than reconnect in a loop.
                self.logger.error("Discord rejected the Rich Presence handshake (\(code)): \(message)")
                self.stop(status: .rejected(message))
                return Self.idleRetryInterval
            } catch {
                self.status = .failed(error.localizedDescription)
                return Self.idleRetryInterval
            }
        }

        // Notice a Discord that quit or restarted even while nothing changes.
        guard await self.client.isAlive() else {
            self.isConnected = false
            self.lastSnapshot = nil
            self.status = .waitingForDiscord
            return Self.reconnectInterval
        }

        let snapshot = self.presentedSnapshot(self.currentSnapshot(), now: Date())
        guard snapshot != self.lastSnapshot else { return Self.pollInterval }

        do {
            let payload = snapshot.map(DiscordPresenceActivity.payload)
            try await self.client.setActivity(payload, processID: ProcessInfo.processInfo.processIdentifier)
            self.lastSnapshot = snapshot
            self.status = .connected
        } catch {
            // Discord quit or the socket died: drop back to reconnecting.
            self.logger.error("Discord presence update failed: \(error.localizedDescription)")
            self.isConnected = false
            self.lastSnapshot = nil
            self.status = .waitingForDiscord
            await self.client.disconnect()
            return Self.reconnectInterval
        }
        return Self.pollInterval
    }

    /// The snapshot to show: a paused one only within `pausedGrace`.
    private func presentedSnapshot(_ snapshot: DiscordPresenceSnapshot?, now: Date) -> DiscordPresenceSnapshot? {
        guard let snapshot, !snapshot.isPlaying else {
            self.pausedSince = nil
            return snapshot
        }
        let since = self.pausedSince ?? now
        self.pausedSince = since
        return Self.isWithinPausedGrace(since: since, now: now) ? snapshot : nil
    }

    nonisolated static func isWithinPausedGrace(since: Date, now: Date) -> Bool {
        now.timeIntervalSince(since) <= self.pausedGrace
    }

    // MARK: - Snapshot

    /// Reads whichever player is actually playing; with neither playing, the
    /// paused video, then the paused song.
    private func currentSnapshot() -> DiscordPresenceSnapshot? {
        let videoSnapshot = self.videoSnapshot()
        let musicSnapshot = self.musicSnapshot()
        if let videoSnapshot, videoSnapshot.isPlaying {
            return videoSnapshot
        }
        if let musicSnapshot, musicSnapshot.isPlaying {
            return musicSnapshot
        }
        return videoSnapshot ?? musicSnapshot
    }

    private func videoSnapshot() -> DiscordPresenceSnapshot? {
        if let youtube = self.youtubePlayerService, let video = youtube.currentVideo {
            return DiscordPresenceSnapshot(
                title: video.title,
                artist: video.channelName,
                artworkURL: video.thumbnailURL,
                isPlaying: youtube.isPlaying,
                duration: youtube.duration,
                isVideo: true,
                startedAt: Self.startInstant(elapsed: youtube.progress, isPlaying: youtube.isPlaying)
            )
        }
        return nil
    }

    private func musicSnapshot() -> DiscordPresenceSnapshot? {
        if let player = self.playerService, let track = player.currentTrack {
            let isPlaying = player.state == .playing
            return DiscordPresenceSnapshot(
                title: track.title,
                artist: track.artists.map(\.name).joined(separator: ", "),
                artworkURL: track.thumbnailURL,
                isPlaying: isPlaying,
                duration: player.duration,
                isVideo: false,
                startedAt: Self.startInstant(elapsed: player.progress, isPlaying: isPlaying)
            )
        }
        return nil
    }

    /// When the track started, in wall-clock terms, rounded to a second so a
    /// steady poll does not report a "new" snapshot on every tick.
    nonisolated static func startInstant(elapsed: TimeInterval, isPlaying: Bool, now: Date = Date()) -> Date? {
        guard isPlaying, elapsed.isFinite, elapsed >= 0 else { return nil }
        return Date(timeIntervalSince1970: (now.timeIntervalSince1970 - elapsed).rounded())
    }
}
