import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubeNotificationBellTests

/// The bell's menu as watch-next carries it (shape captured with api-explorer
/// on a subscribed channel, November 2026; params are placeholders).
@Suite(.serialized, .tags(.parser))
@MainActor
struct YouTubeNotificationBellTests {
    private static func item(_ label: String, icon: String, params: String?, selected: Bool) -> [String: Any] {
        var renderer: [String: Any] = [
            "text": ["simpleText": label],
            "icon": ["iconType": icon],
            "isSelected": selected,
        ]
        renderer["serviceEndpoint"] = params.map { ["modifyChannelNotificationPreferenceEndpoint": ["params": $0]] }
            ?? ["signalServiceEndpoint": [:]]
        return ["menuServiceItemRenderer": renderer]
    }

    private static var subscribeButton: [String: Any] {
        [
            "channelId": "UCtest",
            "subscribed": true,
            "notificationPreferenceButton": ["subscriptionNotificationToggleButtonRenderer": [
                "command": ["commandExecutorCommand": ["commands": [
                    ["openPopupAction": ["popup": ["menuPopupRenderer": ["items": [
                        item("All", icon: "NOTIFICATIONS_ACTIVE", params: "mock-all", selected: false),
                        item("Personalized", icon: "NOTIFICATIONS_NONE", params: "mock-personalized", selected: true),
                        item("None", icon: "NOTIFICATIONS_OFF", params: "mock-none", selected: false),
                        item("Unsubscribe", icon: "PERSON_MINUS", params: nil, selected: false),
                    ]]]]],
                ]]],
            ]],
        ]
    }

    @Test("The bell's options come with their levels and params, the current one marked; Unsubscribe is left out")
    func parsesTheMenu() throws {
        let preference = try #require(WatchNextParser.notificationPreference(from: Self.subscribeButton))
        #expect(preference.channelId == "UCtest")
        #expect(preference.options.map(\.label) == ["All", "Personalized", "None"])
        #expect(preference.options.map(\.level) == [.all, .personalized, .none])
        #expect(preference.current?.params == "mock-personalized")
        #expect(WatchNextParser.notificationPreference(from: ["channelId": "UCtest"]) == nil)
    }

    @Test("Picking an option shows at once and goes to YouTube; a refusal rolls it back")
    func picksAnOption() async throws {
        let preference = try #require(WatchNextParser.notificationPreference(from: Self.subscribeButton))
        let client = MockYouTubeClient()
        client.watchPages = [YouTubeWatchPage(data: WatchNextData(
            videoTitle: "Video", viewCountText: nil, publishedText: nil,
            channel: YouTubeChannel(channelId: "UCtest", name: "Channel"), related: [],
            isSubscribed: true, notificationPreference: preference
        ), askBootstrap: nil)]
        let model = YouTubeWatchViewModel(video: MockYouTubeClient.makeVideo(videoId: "v1"), client: client)
        await model.load()
        let all = try #require(preference.options.first)

        await model.setNotificationPreference(all)
        #expect(model.data.notificationPreference?.current?.params == "mock-all")
        #expect(client.notificationPreferenceChanges == ["mock-all"])

        client.error = URLError(.notConnectedToInternet)
        let none = try #require(preference.options.last)
        await model.setNotificationPreference(none)
        #expect(model.data.notificationPreference?.current?.params == "mock-all")
        client.error = nil

        // Unsubscribing and subscribing again starts the channel over at
        // YouTube's default, which the page doesn't know: no bell until reload.
        #expect(model.notificationPreference != nil)
        let subscriptions = YouTubeChannelSubscriptions.shared
        defer { subscriptions.reset() }
        await subscriptions.setSubscribed(false, channelId: "UCtest", client: client)
        await subscriptions.setSubscribed(true, channelId: "UCtest", client: client)
        #expect(model.notificationPreference == nil)
    }
}
