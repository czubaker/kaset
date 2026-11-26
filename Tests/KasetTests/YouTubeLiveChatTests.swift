import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubeLiveChatTests

/// Live chat, shaped like `live_chat/get_live_chat` captured with api-explorer
/// on a live stream (November 2026); tokens and IDs are placeholders.
@Suite(.serialized, .tags(.parser))
@MainActor
struct YouTubeLiveChatTests {
    private static func textMessage(id: String, author: String, runs: [[String: Any]], badges: [[String: Any]] = []) -> [String: Any] {
        [
            "clickTrackingParams": "mock",
            "addChatItemAction": ["item": ["liveChatTextMessageRenderer": [
                "id": id,
                "authorName": ["simpleText": author],
                "authorExternalChannelId": "UC\(id)",
                "message": ["runs": runs],
                "timestampUsec": "1795688054936310",
                "authorBadges": badges,
            ]]],
        ]
    }

    private static var response: [String: Any] {
        ["continuationContents": ["liveChatContinuation": [
            "actions": [
                textMessage(id: "m1", author: "Viewer", runs: [["text": "hello "], ["emoji": ["emojiId": "👋"]]]),
                textMessage(
                    id: "m2", author: "Mod",
                    runs: [["text": "be nice "], ["emoji": ["isCustomEmoji": true, "shortcuts": [":yt:"]]]],
                    badges: [["liveChatAuthorBadgeRenderer": ["icon": ["iconType": "MODERATOR"]]]]
                ),
                ["addChatItemAction": ["item": ["liveChatViewerEngagementMessageRenderer": ["id": "notice"]]]],
            ],
            "actionPanel": ["liveChatMessageInputRenderer": ["sendButton": ["buttonRenderer": [
                "serviceEndpoint": ["sendLiveChatMessageEndpoint": ["params": "mock-send"]],
            ]]]],
            "continuations": [["invalidationContinuationData": ["continuation": "mock-next", "timeoutMs": 10000]]],
        ]]]
    }

    @Test("A poll brings its text messages, roles, the next token and delay, and whether posting is allowed")
    func parsesAPoll() {
        let page = LiveChatParser.parse(Self.response)
        #expect(page.messages.map(\.id) == ["m1", "m2"])
        #expect(page.messages[0].message == "hello 👋")
        #expect(page.messages[1].message == "be nice :yt:")
        #expect(page.messages[1].isModerator)
        #expect(page.continuation == "mock-next")
        #expect(page.timeoutMs == 10000)
        #expect(page.sendParams == "mock-send")
    }

    @Test("A chat the account can't post in says why")
    func readsTheRestriction() {
        let data: [String: Any] = ["continuationContents": ["liveChatContinuation": [
            "actionPanel": ["liveChatRestrictedParticipationRenderer": ["message": ["runs": [["text": "Subscribers-only mode"]]]]],
        ]]]
        let page = LiveChatParser.parse(data)
        #expect(page.sendParams == nil)
        #expect(page.restrictionMessage == "Subscribers-only mode")
    }

    @Test("The watch page's chat token comes from the conversation bar")
    func readsTheChatToken() {
        let data: [String: Any] = ["contents": ["twoColumnWatchNextResults": ["conversationBar": ["liveChatRenderer": [
            "continuations": [["reloadContinuationData": ["continuation": "mock-chat"]]],
        ]]]]]
        #expect(WatchNextParser.liveChatContinuation(of: data) == "mock-chat")
        #expect(WatchNextParser.liveChatContinuation(of: [:]) == nil)
        let replay: [String: Any] = ["contents": ["twoColumnWatchNextResults": ["conversationBar": ["liveChatRenderer": [
            "isReplay": true,
            "continuations": [["reloadContinuationData": ["continuation": "mock-replay"]]],
        ]]]]]
        #expect(WatchNextParser.liveChatContinuation(of: replay) == nil)
    }

    @Test("Polling follows the tokens, keeps each message once, and posts with the page's params")
    func pollsAndPosts() async {
        let client = MockYouTubeClient()
        let message: (String) -> YouTubeLiveChatMessage = { id in
            YouTubeLiveChatMessage(
                id: id, author: "A", authorAvatarURL: nil, authorChannelId: nil, message: id, timestampText: nil,
                isVerified: false, isModerator: false, isMember: false, isOwner: false
            )
        }
        client.liveChatPages["mock-1"] = YouTubeLiveChatPage(
            messages: [message("a"), message("b")], continuation: "mock-2", timeoutMs: 0, sendParams: "mock-send"
        )
        client.liveChatPages["mock-2"] = YouTubeLiveChatPage(
            messages: [message("b"), message("c")], continuation: nil, timeoutMs: 0, sendParams: nil
        )
        let model = YouTubeLiveChatViewModel(client: client)

        await model.run(continuation: "mock-1")
        #expect(client.liveChatRequests == ["mock-1", "mock-2"])
        #expect(model.isFinished)
        #expect(!model.didFail)
        #expect(model.messages.map(\.id) == ["a", "b", "c"])
        #expect(model.canSend)

        #expect(await model.send("  hi  "))
        #expect(client.sentLiveChatMessages.map(\.text) == ["hi"])
        #expect(client.sentLiveChatMessages.map(\.params) == ["mock-send"])
        #expect(await model.send("   ") == false)
    }

    @Test("The server's poll delay is held between one and fifteen seconds")
    func boundsThePollDelay() {
        #expect(YouTubeLiveChatViewModel.pollInterval(milliseconds: 0) == .seconds(1))
        #expect(YouTubeLiveChatViewModel.pollInterval(milliseconds: 10000) == .seconds(10))
        #expect(YouTubeLiveChatViewModel.pollInterval(milliseconds: 600_000) == .seconds(15))
    }
}
