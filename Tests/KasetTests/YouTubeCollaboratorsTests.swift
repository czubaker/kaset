import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubeCollaboratorsTests

/// A collaboration upload's owner, shaped like a watch-next response captured
/// with api-explorer (November 2026); IDs and keys are placeholders.
@Suite(.tags(.parser))
struct YouTubeCollaboratorsTests {
    private static func listItem(name: String, channelId: String, subtitle: String, stateKey: String, verified: Bool) -> [String: Any] {
        var title: [String: Any] = ["content": name]
        if verified {
            title["attachmentRuns"] = [["element": ["type": ["imageType": ["image": ["sources": [
                ["clientResource": ["imageName": "CHECK_CIRCLE_FILLED"]],
            ]]]]]]]
        }
        return ["listItemViewModel": [
            "title": title,
            "subtitle": ["content": subtitle],
            "leadingAccessory": ["avatarViewModel": ["image": ["sources": [["url": "https://yt3.ggpht.com/\(channelId)"]]]]],
            "trailingButtons": ["buttons": [["subscribeButtonViewModel": [
                "channelId": channelId,
                "stateEntityStoreKey": stateKey,
            ]]]],
        ]]
    }

    private static var response: [String: Any] {
        let owner: [String: Any] = [
            "attributedTitle": ["content": "First and Second"],
            "navigationEndpoint": ["showDialogCommand": ["panelLoadingStrategy": ["inlineContent": ["dialogViewModel": [
                "customContent": ["listViewModel": ["listItems": [
                    Self.listItem(
                        name: "First", channelId: "UCfirst", subtitle: "\u{200E}\u{2068}@first\u{2069} • \u{2068}11.1M subscribers\u{2069}",
                        stateKey: "mock-key-1", verified: true
                    ),
                    Self.listItem(
                        name: "Second", channelId: "UCsecond", subtitle: "\u{2068}@second\u{2069}",
                        stateKey: "mock-key-2", verified: false
                    ),
                ]]],
            ]]]]],
        ]
        return [
            "contents": ["twoColumnWatchNextResults": ["results": ["results": ["contents": [
                ["videoPrimaryInfoRenderer": ["title": ["runs": [["text": "Video"]]]]],
                ["videoSecondaryInfoRenderer": ["owner": ["videoOwnerRenderer": owner]]],
            ]]]]],
            "frameworkUpdates": ["entityBatchUpdate": ["mutations": [
                ["payload": ["subscriptionStateEntity": ["key": "mock-key-2", "subscribed": true]]],
            ]]],
        ]
    }

    @Test("A collaboration upload lists its channels, each with what the page knew about it")
    func parsesCollaborators() throws {
        let data = WatchNextParser.parse(Self.response)
        #expect(data.collaborators.map(\.channelId) == ["UCfirst", "UCsecond"])
        let first = try #require(data.collaborators.first)
        #expect(first.isVerified)
        #expect(first.handle == "@first")
        #expect(first.subscriberText == "11.1M subscribers")
        #expect(first.detail == "@first • 11.1M subscribers")
        #expect(first.avatarURL?.absoluteString == "https://yt3.ggpht.com/UCfirst")
        #expect(!first.isSubscribed)
        #expect(data.collaborators.last?.isSubscribed == true)
        #expect(data.collaborators.last?.subscriberText == nil)
    }

    @Test("Its channel goes by the names together and links to the first")
    func namesTheChannelsTogether() throws {
        let channel = try #require(WatchNextParser.parse(Self.response).channel)
        #expect(channel.name == "First and Second")
        #expect(channel.channelId == "UCfirst")
    }
}
