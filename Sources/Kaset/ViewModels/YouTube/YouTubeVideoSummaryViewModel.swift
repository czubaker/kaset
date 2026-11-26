import Foundation
import Observation

// MARK: - YouTubeVideoSummaryError

/// How summarizing failed, apart from Apple Intelligence's own error types
/// (macOS 26 only).
enum YouTubeVideoSummaryError: Error, Equatable {
    case unavailable
    case declined
    case failed
}

// MARK: - YouTubeVideoSummaryViewModel

/// Summarizes one video with Apple Intelligence, on this Mac, from the text of
/// its captions. Nothing runs until the user asks.
@MainActor
@Observable
final class YouTubeVideoSummaryViewModel {
    enum State: Equatable {
        case idle
        case fetchingCaptions
        case readingPart(Int, of: Int)
        /// What is written so far.
        case writing(YouTubeVideoSummary?)
        case done(YouTubeVideoSummary)
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// The video has no captions to read, or too little in them.
        case noCaptions
        /// Apple Intelligence declined the content.
        case declined
        case unavailable
        case other
    }

    typealias Summarizer = @MainActor (
        _ title: String,
        _ transcript: String,
        _ onProgress: @escaping @MainActor (YouTubeVideoSummaryProgress) -> Void
    ) async throws -> YouTubeVideoSummary

    private(set) var state: State = .idle

    var isWorking: Bool {
        switch self.state {
        case .fetchingCaptions, .readingPart, .writing: true
        case .idle, .done, .failed: false
        }
    }

    let videoId: String
    private let client: any YouTubeClientProtocol
    private let summarizer: Summarizer
    private let preferredLanguages: [String]
    private var task: Task<Void, Never>?
    /// Bumped by every run and by `cancel()`; a run whose number is stale
    /// writes nothing.
    private var runID = 0
    private let logger = DiagnosticsLogger.ai

    init(
        videoId: String,
        client: any YouTubeClientProtocol,
        preferredLanguages: [String] = Locale.preferredLanguages,
        summarizer: @escaping Summarizer = YouTubeVideoSummaryViewModel.appleIntelligence
    ) {
        self.videoId = videoId
        self.client = client
        self.preferredLanguages = preferredLanguages
        self.summarizer = summarizer
    }

    /// Starts summarizing, unless it already is.
    func summarize(title: String) {
        guard !self.isWorking else { return }
        self.task = Task { await self.run(title: title) }
    }

    /// Stops a summary in progress, as when the page goes away.
    func cancel() {
        self.task?.cancel()
        self.task = nil
        self.runID += 1
        if self.isWorking {
            self.state = .idle
        }
    }

    /// Runs one summary; internal so tests can await it.
    func run(title: String) async {
        self.runID += 1
        let runID = self.runID
        // Writes `state` only while this run is the current one.
        func update(_ state: State) {
            guard runID == self.runID, !Task.isCancelled else { return }
            self.state = state
        }

        update(.fetchingCaptions)
        do {
            let tracks = try await self.client.getTranscriptTracks(videoId: self.videoId)
            guard let track = YouTubeCaptionsParser.preferredTrack(among: tracks, preferredLanguages: self.preferredLanguages)
            else {
                update(.failed(.noCaptions))
                return
            }
            let transcript = try await self.client.getTranscript(track)
            guard transcript.count >= YouTubeVideoSummaryPlan.minimumLength else {
                update(.failed(.noCaptions))
                return
            }
            guard runID == self.runID, !Task.isCancelled else { return }
            let summary = try await self.summarizer(title, transcript) { progress in
                switch progress {
                case let .readingPart(part, total):
                    update(.readingPart(part, of: total))
                case let .writing(partial):
                    update(.writing(partial))
                }
            }
            update(.done(summary))
        } catch {
            // A cancelled run (CancellationError, or URLError.cancelled from a
            // fetch) is stale by now and says nothing.
            guard runID == self.runID, !Task.isCancelled else { return }
            self.logger.error("Video summary failed: \(error.localizedDescription)")
            self.state = .failed(Self.failure(for: error))
        }
    }

    private static func failure(for error: Error) -> Failure {
        switch error as? YouTubeVideoSummaryError {
        case .declined: .declined
        case .unavailable: .unavailable
        case .failed, nil: .other
        }
    }

    /// Apple Intelligence on macOS 26 and later.
    static func appleIntelligence(
        title: String,
        transcript: String,
        onProgress: @escaping @MainActor (YouTubeVideoSummaryProgress) -> Void
    ) async throws -> YouTubeVideoSummary {
        guard #available(macOS 26.0, *) else {
            throw YouTubeVideoSummaryError.unavailable
        }
        do {
            return try await FoundationModelsService.shared.summarizeVideo(
                title: title,
                transcript: transcript,
                onProgress: onProgress
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            switch AIErrorHandler.handle(error) {
            case .contentBlocked: throw YouTubeVideoSummaryError.declined
            case .notAvailable, .modelNotReady: throw YouTubeVideoSummaryError.unavailable
            case .cancelled: throw CancellationError()
            default: throw YouTubeVideoSummaryError.failed
            }
        }
    }

    /// Whether Apple Intelligence can summarize here.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            FoundationModelsService.shared.canSummarizeVideos
        } else {
            false
        }
    }
}
