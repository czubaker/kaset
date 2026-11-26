import Foundation
import Observation

// MARK: - YouTubeLiveChatViewModel

/// A live stream's chat while its watch page is open: polls
/// `live_chat/get_live_chat` on the server's schedule, keeps the latest
/// messages, and posts when YouTube allows the account to. Ported from
/// KasetPlus (github.com/Yoddikko/kasetPlus, MIT).
@MainActor
@Observable
final class YouTubeLiveChatViewModel {
    /// The latest messages, oldest first.
    private(set) var messages: [YouTubeLiveChatMessage] = []
    /// Whether the account may post (YouTube sent send params).
    var canSend: Bool {
        self.sendParams != nil
    }

    /// The chat ended, or stopped answering; no more polls.
    private(set) var isFinished = false
    /// Polling stopped after repeated failures.
    private(set) var didFail = false
    /// Why the account can't post, when YouTube says.
    private(set) var restrictionMessage: String?
    private(set) var isSending = false
    private(set) var sendFailed = false

    private let client: any YouTubeClientProtocol
    private var sendParams: String?
    private let logger = DiagnosticsLogger.api

    /// How many messages to keep: a busy chat posts many a second.
    static let maximumMessages = 200
    /// Bounds on the server's poll delay.
    nonisolated static let minimumPollInterval: Duration = .seconds(1)
    nonisolated static let maximumPollInterval: Duration = .seconds(15)

    init(client: any YouTubeClientProtocol) {
        self.client = client
    }

    /// Polls until the chat ends or the caller's task is cancelled (the page
    /// goes away).
    func run(continuation: String) async {
        self.isFinished = false
        self.didFail = false
        defer {
            if !Task.isCancelled {
                self.isFinished = true
            }
        }
        var token: String? = continuation
        var failures = 0
        while let current = token, !Task.isCancelled {
            do {
                let page = try await self.client.getLiveChat(continuation: current)
                guard !Task.isCancelled else { return }
                self.append(page.messages)
                if let params = page.sendParams {
                    self.sendParams = params
                    self.restrictionMessage = nil
                } else if let message = page.restrictionMessage {
                    self.restrictionMessage = message
                }
                token = page.continuation
                failures = 0
                try? await Task.sleep(for: Self.pollInterval(milliseconds: page.timeoutMs))
            } catch {
                guard !(error is CancellationError) else { return }
                failures += 1
                self.logger.error("Failed to load live chat: \(error.localizedDescription)")
                guard failures < 5 else {
                    self.didFail = true
                    return
                }
                try? await Task.sleep(for: .seconds(5 * failures))
            }
        }
    }

    func append(_ newMessages: [YouTubeLiveChatMessage]) {
        let known = Set(self.messages.map(\.id))
        let fresh = newMessages.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        self.messages = Array((self.messages + fresh).suffix(Self.maximumMessages))
    }

    nonisolated static func pollInterval(milliseconds: Int) -> Duration {
        min(max(.milliseconds(milliseconds), self.minimumPollInterval), self.maximumPollInterval)
    }

    /// Posts `text`; returns whether YouTube took it. The message shows when
    /// the next poll brings it back.
    @discardableResult
    func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let params = self.sendParams, !self.isSending else { return false }
        self.isSending = true
        self.sendFailed = false
        defer { self.isSending = false }
        do {
            try await self.client.sendLiveChatMessage(text: trimmed, params: params)
            return true
        } catch {
            self.logger.error("Failed to send a live chat message: \(error.localizedDescription)")
            self.sendFailed = true
            return false
        }
    }
}
