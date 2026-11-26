import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubeNotificationsTests

/// The notification inbox as `notification/get_notification_menu` returns it
/// (captured with api-explorer, November 2026), and the bell's badge.
@Suite(.serialized, .tags(.parser))
@MainActor
struct YouTubeNotificationsTests {
    private static func item(
        id: String,
        message: String,
        endpoint: [String: Any],
        read: Bool = false,
        videoThumbnail: String? = nil
    ) -> [String: Any] {
        var renderer: [String: Any] = [
            "notificationId": id,
            "shortMessage": ["simpleText": message],
            "sentTimeText": ["simpleText": "3 hours ago"],
            "read": read,
            "navigationEndpoint": endpoint,
            "thumbnail": ["thumbnails": [["url": "https://yt3.ggpht.com/avatar", "width": 88, "height": 88]]],
        ]
        if let videoThumbnail {
            renderer["videoThumbnail"] = ["thumbnails": [["url": videoThumbnail, "width": 640, "height": 360]]]
        }
        return ["notificationRenderer": renderer]
    }

    private static func response(_ items: [[String: Any]]) -> [String: Any] {
        ["actions": [["openPopupAction": ["popup": ["multiPageMenuRenderer": ["sections": [
            ["multiPageMenuNotificationSectionRenderer": ["items": items + [["continuationItemRenderer": [:]]]]],
        ]]]]]]]
    }

    private static var inbox: [String: Any] {
        response([
            item(id: "n-comment", message: "Your comment got a heart", endpoint: ["getCommentsFromInboxCommand": [:]]),
            item(
                id: "n-short",
                message: "Channel uploaded a Short",
                endpoint: ["reelWatchEndpoint": ["videoId": "short01"]],
                videoThumbnail: "https://i.ytimg.com/vi/short01/hqdefault.jpg"
            ),
            item(
                id: "n-video",
                message: "Channel uploaded: A video",
                endpoint: ["watchEndpoint": ["videoId": "video01"]],
                read: true,
                videoThumbnail: "https://i.ytimg.com/vi/video01/hqdefault.jpg"
            ),
            item(id: "n-video", message: "Duplicate", endpoint: ["watchEndpoint": ["videoId": "video01"]]),
        ])
    }

    private static func freshDefaults() -> UserDefaults {
        let name = "YouTubeNotificationsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static func notification(_ id: String, isRead: Bool = false) -> YouTubeNotification {
        YouTubeNotification(
            id: id,
            message: id,
            sentTimeText: nil,
            thumbnailURL: nil,
            video: YouTubeVideo(videoId: id, title: id),
            isRead: isRead
        )
    }

    @Test("Videos and Shorts are kept, other notifications and duplicates dropped")
    func parsesVideosAndShorts() {
        let notifications = YouTubeNotificationsParser.parse(Self.inbox)
        #expect(notifications.map(\.id) == ["n-short", "n-video"])

        let short = notifications[0]
        #expect(short.video.videoId == "short01")
        #expect(short.video.isShort)
        #expect(short.message == "Channel uploaded a Short")
        #expect(short.sentTimeText == "3 hours ago")
        #expect(short.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/short01/hqdefault.jpg")
        #expect(!short.isRead)

        let video = notifications[1]
        #expect(video.video.videoId == "video01")
        #expect(!video.video.isShort)
        #expect(video.isRead)
    }

    @Test("Without the video's still, the channel's avatar is the thumbnail")
    func fallsBackToTheAvatar() {
        let data = Self.response([Self.item(id: "n1", message: "New", endpoint: ["watchEndpoint": ["videoId": "v1"]])])
        #expect(YouTubeNotificationsParser.parse(data).first?.thumbnailURL?.absoluteString == "https://yt3.ggpht.com/avatar")
    }

    @Test("The badge counts unread notifications until the inbox is opened")
    func openingMarksSeen() async {
        let client = MockYouTubeClient()
        client.notifications = [Self.notification("a"), Self.notification("b"), Self.notification("c", isRead: true)]
        let defaults = Self.freshDefaults()
        let viewModel = YouTubeNotificationsViewModel(client: client, defaults: defaults)

        let poll = Task { await viewModel.poll() }
        while viewModel.notifications.isEmpty {
            await Task.yield()
        }
        poll.cancel()
        #expect(viewModel.unseenCount == 2)

        await viewModel.open()
        #expect(viewModel.unseenCount == 0)
        #expect(viewModel.isNew(Self.notification("a")))
        #expect(!viewModel.isNew(Self.notification("c")))

        // A new arrival lights the badge again; what was seen stays seen,
        // also for the next launch.
        client.notifications.insert(Self.notification("d"), at: 0)
        let relaunched = YouTubeNotificationsViewModel(client: client, defaults: defaults)
        await relaunched.open()
        #expect(relaunched.isNew(Self.notification("d")))
        #expect(!relaunched.isNew(Self.notification("a")))
    }

    @Test("Another account's inbox doesn't forget what was seen in the first, and the newest are kept")
    func remembersAcrossAccounts() async {
        let client = MockYouTubeClient()
        client.notifications = [Self.notification("a1")]
        let defaults = Self.freshDefaults()
        await YouTubeNotificationsViewModel(client: client, defaults: defaults).open()

        // Another account: a new model polls and opens its own inbox.
        client.notifications = [Self.notification("b1"), Self.notification("b2")]
        let other = YouTubeNotificationsViewModel(client: client, defaults: defaults)
        await other.open()
        #expect(defaults.stringArray(forKey: YouTubeNotificationsViewModel.seenKey) == ["b1", "b2", "a1"])

        // Back on the first account, its notification is still seen.
        client.notifications = [Self.notification("a1")]
        let first = YouTubeNotificationsViewModel(client: client, defaults: defaults)
        let poll = Task { await first.poll() }
        while first.notifications.isEmpty {
            await Task.yield()
        }
        poll.cancel()
        #expect(first.unseenCount == 0)

        let many = (0 ..< YouTubeNotificationsViewModel.maximumSeenIDs + 5).map { Self.notification("n\($0)") }
        client.notifications = many
        await first.open()
        let stored = defaults.stringArray(forKey: YouTubeNotificationsViewModel.seenKey) ?? []
        #expect(stored.count == YouTubeNotificationsViewModel.maximumSeenIDs)
        #expect(stored.first == "n0")
    }

    @Test("A failed load keeps the last inbox and says so")
    func failureKeepsTheInbox() async {
        let client = MockYouTubeClient()
        client.notifications = [Self.notification("a")]
        let viewModel = YouTubeNotificationsViewModel(client: client, defaults: Self.freshDefaults())
        await viewModel.open()

        client.error = YTMusicError.networkError(underlying: URLError(.notConnectedToInternet))
        await viewModel.open()
        #expect(viewModel.didFail)
        #expect(viewModel.notifications.map(\.id) == ["a"])
    }
}
