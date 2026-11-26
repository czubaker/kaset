import Foundation
import Observation

// MARK: - YouTubeLyricsViewModel

/// One video's lyrics from LRCLib, looked up from its title and channel, or
/// from what the user types when that finds the wrong song or none.
@MainActor
@Observable
final class YouTubeLyricsViewModel {
    enum State: Equatable {
        case idle
        case searching
        case found(YouTubeLyricsLookup.Match)
        case notFound
        case failed
        /// The search field, after the user asked to search again.
        case editing
    }

    private(set) var state: State = .idle
    /// What the lookup searches for; editable.
    var query: YouTubeLyricsQuery

    let videoId: String
    private let lookup: YouTubeLyricsLookup
    private var task: Task<Void, Never>?
    private var generation = 0
    private let logger = DiagnosticsLogger.player

    init(videoId: String, title: String, channelName: String?, lookup: YouTubeLyricsLookup = YouTubeLyricsLookup()) {
        self.videoId = videoId
        self.query = YouTubeLyricsQuery(videoTitle: title, channelName: channelName)
        self.lookup = lookup
    }

    /// Takes the full title and channel once the watch page has them, while
    /// nothing has been looked up yet.
    func updateQuery(title: String, channelName: String?) {
        guard self.state == .idle else { return }
        self.query = YouTubeLyricsQuery(videoTitle: title, channelName: channelName)
    }

    /// Looks the lyrics up, replacing a lookup in progress.
    func find(duration: TimeInterval?) {
        self.task?.cancel()
        self.task = Task { await self.run(duration: duration) }
    }

    /// Looks up what the user typed, as free text, taking the closest song
    /// whatever its length (a live take, a remix).
    func search(_ text: String, duration: TimeInterval?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.query = YouTubeLyricsQuery(artist: nil, title: trimmed)
        self.task?.cancel()
        self.task = Task { await self.run(duration: duration, enforcingLength: false) }
    }

    /// Back to the search field, as when the wrong song was found.
    func showSearch() {
        self.task?.cancel()
        self.generation += 1
        self.state = .editing
    }

    func cancel() {
        self.task?.cancel()
        self.task = nil
        if self.state == .searching {
            self.state = .idle
        }
    }

    /// Runs one lookup; internal so tests can await it.
    func run(duration: TimeInterval?, enforcingLength: Bool = true) async {
        self.generation += 1
        let generation = self.generation
        self.state = .searching
        do {
            let match = try await self.lookup.find(self.query, duration: duration, enforcingLength: enforcingLength)
            guard generation == self.generation, !Task.isCancelled else { return }
            self.state = match.map(State.found) ?? .notFound
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            self.logger.error("YouTube lyrics lookup failed: \(error.localizedDescription)")
            self.state = .failed
        }
    }
}
