import Foundation
import Testing
@testable import Kaset

// MARK: - ChannelTabFixture

/// Channel browse shapes verified with api-explorer in November 2026
/// (tokens, params, and IDs are placeholders).
private enum ChannelTabFixture {
    static func tab(_ title: String, path: String, params: String, selected: Bool = false, content: [String: Any]? = nil) -> [String: Any] {
        var renderer: [String: Any] = [
            "title": title,
            "selected": selected,
            "endpoint": [
                "browseEndpoint": ["browseId": "UCtest", "params": params],
                "commandMetadata": ["webCommandMetadata": ["url": "/@test/\(path)"]],
            ],
        ]
        if let content {
            renderer["content"] = content
        }
        return ["tabRenderer": renderer]
    }

    static func videoLockup(_ id: String) -> [String: Any] {
        [
            "richItemRenderer": [
                "content": [
                    "lockupViewModel": [
                        "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                        "contentId": id,
                        "rendererContext": ["commandContext": ["onTap": ["innertubeCommand": ["watchEndpoint": ["videoId": id]]]]],
                        "metadata": ["lockupMetadataViewModel": ["title": ["content": "Video \(id)"]]],
                    ],
                ],
            ],
        ]
    }

    static func continuationItem(_ token: String) -> [String: Any] {
        ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": token]]]]
    }

    static func chipBar(selected: String) -> [String: Any] {
        [
            "chipBarViewModel": [
                "chips": ["Latest", "Popular", "Oldest"].map { title in
                    [
                        "chipViewModel": [
                            "text": title,
                            "selected": title == selected,
                            "tapCommand": ["innertubeCommand": ["continuationCommand": ["token": "mock-sort-\(title)"]]],
                        ],
                    ]
                },
            ],
        ]
    }

    static func browse(tabs: [[String: Any]]) -> [String: Any] {
        ["contents": ["twoColumnBrowseResultsRenderer": ["tabs": tabs]]]
    }

    static var videosTab: [String: Any] {
        self.browse(tabs: [
            self.tab("Home", path: "featured", params: "mock-home"),
            self.tab("Videos", path: "videos", params: "mock-videos", selected: true, content: [
                "richGridRenderer": [
                    "header": self.chipBar(selected: "Latest"),
                    "contents": [self.videoLockup("v1"), self.videoLockup("v2"), self.continuationItem("mock-next")],
                ],
            ]),
            self.tab("Shorts", path: "shorts", params: "mock-shorts"),
            self.tab("Live", path: "streams", params: "mock-live"),
            self.tab("Playlists", path: "playlists", params: "mock-playlists"),
            self.tab("Posts", path: "posts", params: "mock-posts"),
            self.tab("Store", path: "store", params: "mock-store"),
        ])
    }
}

// MARK: - ChannelTabParserTests

@Suite("ChannelTabParser", .tags(.parser))
struct ChannelTabParserTests {
    @Test("Tabs Kaset can show come with their kinds, from their URLs; others are left out")
    func parsesTabs() {
        let tabs = ChannelTabParser.tabs(from: ChannelTabFixture.videosTab)
        let expectedKinds: [YouTubeChannelTab.Kind] = [.home, .videos, .shorts, .live, .playlists]
        #expect(tabs.map(\.kind) == expectedKinds)
        #expect(tabs.map(\.params) == ["mock-home", "mock-videos", "mock-shorts", "mock-live", "mock-playlists"])
    }

    @Test("The selected tab's page brings its videos, sorts, and next-page token")
    func parsesPage() {
        let page = ChannelTabParser.parsePage(ChannelTabFixture.videosTab)
        #expect(page.videos.map(\.videoId) == ["v1", "v2"])
        #expect(page.continuation == "mock-next")
        #expect(page.sortOptions.map(\.title) == ["Latest", "Popular", "Oldest"])
        #expect(page.sortOptions.map(\.isSelected) == [true, false, false])
        #expect(page.sortOptions[1].continuation == "mock-sort-Popular")
    }

    @Test("A sort's reload brings the new selection; a next page appends")
    func parsesContinuations() {
        let reload: [String: Any] = [
            "onResponseReceivedActions": [
                ["reloadContinuationItemsCommand": ["continuationItems": [ChannelTabFixture.chipBar(selected: "Popular")]]],
                ["reloadContinuationItemsCommand": [
                    "continuationItems": [ChannelTabFixture.videoLockup("p1"), ChannelTabFixture.continuationItem("mock-popular-next")],
                ]],
            ],
        ]
        let append: [String: Any] = [
            "onResponseReceivedActions": [
                ["appendContinuationItemsAction": ["continuationItems": [ChannelTabFixture.videoLockup("v3")]]],
            ],
        ]

        let sorted = ChannelTabParser.parseContinuation(reload)
        let next = ChannelTabParser.parseContinuation(append)

        #expect(sorted.videos.map(\.videoId) == ["p1"])
        #expect(sorted.sortOptions.first(where: \.isSelected)?.title == "Popular")
        #expect(sorted.continuation == "mock-popular-next")
        #expect(next.videos.map(\.videoId) == ["v3"])
        #expect(next.continuation == nil)
    }
}

// MARK: - YouTubeChannelViewModelTabTests

@Suite("YouTubeChannelViewModel tabs", .serialized, .tags(.viewModel))
@MainActor
struct YouTubeChannelViewModelTabTests {
    private let videosTab = YouTubeChannelTab(kind: .videos, title: "Videos", params: "mock-videos")

    private func video(_ id: String) -> YouTubeVideo {
        MockYouTubeClient.makeVideo(videoId: id)
    }

    @Test("Picking a tab loads it once; the next page appends; a sort replaces")
    func loadsPagesAndSorts() async {
        let client = MockYouTubeClient()
        let sorts = [
            YouTubeChannelSortOption(title: "Latest", continuation: "mock-latest", isSelected: true),
            YouTubeChannelSortOption(title: "Popular", continuation: "mock-popular", isSelected: false),
        ]
        client.channelTabPages["mock-videos"] = YouTubeChannelTabPage(
            videos: [self.video("v1")], sortOptions: sorts, continuation: "mock-next"
        )
        client.channelTabContinuations["mock-next"] = YouTubeChannelTabPage(videos: [self.video("v2")])
        client.channelTabContinuations["mock-popular"] = YouTubeChannelTabPage(videos: [self.video("p1")])
        let model = YouTubeChannelViewModel(channelId: "UCtest", client: client)

        await model.select(self.videosTab)
        await model.select(self.videosTab)
        #expect(client.channelTabRequests == ["mock-videos"])

        await model.loadMore()
        #expect(model.page(for: self.videosTab)?.videos.map(\.videoId) == ["v1", "v2"])
        #expect(model.page(for: self.videosTab)?.continuation == nil)

        await model.selectSort(sorts[1])
        #expect(model.page(for: self.videosTab)?.videos.map(\.videoId) == ["p1"])
        // The reload brought no chips, so the old ones carry the new selection.
        #expect(model.page(for: self.videosTab)?.sortOptions.first(where: \.isSelected)?.title == "Popular")
    }
}
