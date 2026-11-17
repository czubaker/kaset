import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubePlayerBarDetailsTests

@Suite("YouTubePlayerBarDetails", .tags(.model))
struct YouTubePlayerBarDetailsTests {
    @Test("Both blocks start as the title over the channel, as the bar always showed")
    func standardLines() {
        let details = YouTubePlayerBarDetails.standard
        #expect(details.lines(for: .videoInfo) == .standard)
        #expect(details.lines(for: .channelInfo) == .standard)
        #expect(details.lines(for: .thumbnail) == nil)
        #expect(YouTubePlayerBarDetailLines.standard.fields == [.title, .channel])
    }

    @Test("Decoding keeps known fields, falls back for unknown ones, and keeps an empty second line")
    func decodesLeniently() throws {
        let json = Data("""
        {"videoInfo": {"first": "views", "second": "bogus"}, "channelInfo": {"first": "subscribers"}}
        """.utf8)
        let details = try JSONDecoder().decode(YouTubePlayerBarDetails.self, from: json)
        let expectedVideoInfo = YouTubePlayerBarDetailLines(first: .views, second: .channel)
        let expectedChannelInfo = YouTubePlayerBarDetailLines(first: .subscribers, second: nil)

        #expect(details.videoInfo == expectedVideoInfo)
        #expect(details.channelInfo == expectedChannelInfo)

        let roundTrip = try JSONDecoder().decode(YouTubePlayerBarDetails.self, from: JSONEncoder().encode(details))
        #expect(roundTrip == details)
    }

    @Test("Fields come only from the details blocks on the bar")
    func fieldsOnBar() {
        var details = YouTubePlayerBarDetails.standard
        details.setLines(YouTubePlayerBarDetailLines(first: .viewsAndDate, second: .subscribers), for: .channelInfo)
        let standardBar = PlayerBarConfiguration<YouTubePlayerBarItem>.standard
        let withChannelBlock = PlayerBarConfiguration<YouTubePlayerBarItem>(
            leading: [.channelInfo], center: [.playPause], trailing: [], settingsMenu: []
        )
        let expectedStandard: Set<YouTubePlayerBarDetailField> = [.title, .channel]
        let expectedChannelBlock: Set<YouTubePlayerBarDetailField> = [.viewsAndDate, .subscribers]

        #expect(details.fields(on: standardBar) == expectedStandard)
        #expect(details.fields(on: withChannelBlock) == expectedChannelBlock)
    }
}

// MARK: - YouTubeWatchPageLayoutTests

@Suite("YouTubeWatchPageLayout", .tags(.model))
struct YouTubeWatchPageLayoutTests {
    private let standardBar = PlayerBarConfiguration<YouTubePlayerBarItem>.standard
    private let details = YouTubePlayerBarDetails.standard

    @Test("Everything shows by default")
    func showsEverythingByDefault() {
        let layout = YouTubeWatchPageLayout.standard
        for element in YouTubeWatchPageElement.allCases {
            #expect(layout.shows(element, playerBar: self.standardBar, details: self.details))
        }
    }

    @Test("Hidden elements stay hidden; the rest show")
    func hidesChosenElements() {
        var layout = YouTubeWatchPageLayout.standard
        layout.hiddenElements = [.views, .related]

        #expect(!layout.shows(.views, playerBar: self.standardBar, details: self.details))
        #expect(!layout.shows(.related, playerBar: self.standardBar, details: self.details))
        #expect(layout.shows(.date, playerBar: self.standardBar, details: self.details))
    }

    @Test("Hiding what the bar shows follows the bar's items and lines")
    func hidesWhatTheBarShows() {
        var layout = YouTubeWatchPageLayout.standard
        layout.hidesPlayerBarItems = true
        var details = self.details
        details.setLines(YouTubePlayerBarDetailLines(first: .title, second: .viewsAndDate), for: .videoInfo)
        let bar = PlayerBarConfiguration<YouTubePlayerBarItem>(
            leading: [.thumbnail, .videoInfo, .subscribe], center: [.playPause], trailing: [], settingsMenu: []
        )

        #expect(!layout.shows(.title, playerBar: bar, details: details))
        #expect(!layout.shows(.views, playerBar: bar, details: details))
        #expect(!layout.shows(.date, playerBar: bar, details: details))
        #expect(!layout.shows(.subscribeButton, playerBar: bar, details: details))
        #expect(layout.shows(.channel, playerBar: bar, details: details))
        #expect(layout.shows(.subscriberCount, playerBar: bar, details: details))
        #expect(layout.shows(.comments, playerBar: bar, details: details))
    }

    @Test("Decoding drops elements it doesn't know")
    func decodesLeniently() throws {
        let json = Data(#"{"hiddenElements": ["views", "hologram"], "hidesPlayerBarItems": true}"#.utf8)
        let layout = try JSONDecoder().decode(YouTubeWatchPageLayout.self, from: json)
        let expected: Set<YouTubeWatchPageElement> = [.views]

        #expect(layout.hiddenElements == expected)
        #expect(layout.hidesPlayerBarItems)
    }
}

// MARK: - YouTubeChannelSubscriptionsTests

@Suite("YouTubeChannelSubscriptions", .serialized, .tags(.viewModel))
@MainActor
struct YouTubeChannelSubscriptionsTests {
    @Test("A change shows at once and goes through")
    func subscribes() async {
        let subscriptions = YouTubeChannelSubscriptions()
        let client = MockYouTubeClient()
        subscriptions.seed(false, channelId: "UCtest")

        let changed = await subscriptions.setSubscribed(true, channelId: "UCtest", client: client)

        #expect(changed)
        #expect(subscriptions.isSubscribed(to: "UCtest") == true)
        #expect(client.subscriptionChanges.map(\.channelId) == ["UCtest"])
    }

    @Test("A refused change rolls back")
    func rollsBack() async {
        let subscriptions = YouTubeChannelSubscriptions()
        let client = MockYouTubeClient()
        client.error = YTMusicError.apiError(message: "mock failure", code: nil)
        subscriptions.seed(true, channelId: "UCtest")

        let changed = await subscriptions.setSubscribed(false, channelId: "UCtest", client: client)

        #expect(!changed)
        #expect(subscriptions.isSubscribed(to: "UCtest") == true)
    }

    @Test("Resetting forgets every channel")
    func resets() {
        let subscriptions = YouTubeChannelSubscriptions()
        subscriptions.seed(true, channelId: "UCtest")
        subscriptions.reset()
        #expect(subscriptions.isSubscribed(to: "UCtest") == nil)
    }
}
