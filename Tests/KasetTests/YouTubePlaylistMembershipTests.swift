import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubeWatchPageCoveringTests

@Suite("YouTubeWatchPageCovering", .tags(.model))
struct YouTubeWatchPageCoveringTests {
    private let video = MockYouTubeClient.makeVideo(videoId: "watch-video")
    private let other = MockYouTubeClient.makeVideo(videoId: "other-video")

    @Test("A channel pushed over a watch page covers its video")
    func coversOnPush() {
        let change = YouTubeWatchPageCovering.change(
            from: [.watch(self.video)],
            to: [.watch(self.video), .channel(channelId: "UCtest")]
        )
        #expect(change == .covered(videoId: "watch-video"))
    }

    @Test("A video pushed over a video doesn't count: the new page takes playback")
    func ignoresVideoOverVideo() {
        let change = YouTubeWatchPageCovering.change(from: [.watch(self.video)], to: [.watch(self.video), .watch(self.other)])
        #expect(change == nil)
    }

    @Test("Going back to the watch page reveals it; leaving it doesn't")
    func revealsOnPop() {
        let revealed = YouTubeWatchPageCovering.change(
            from: [.watch(self.video), .playlist(playlistId: "PLtest")],
            to: [.watch(self.video)]
        )
        let left = YouTubeWatchPageCovering.change(from: [.watch(self.video)], to: [])
        #expect(revealed == .revealed(self.video))
        #expect(left == nil)
    }
}

// MARK: - YouTubePlaylistMembershipTests

@Suite("YouTubePlaylistMembership", .serialized, .tags(.viewModel))
@MainActor
struct YouTubePlaylistMembershipTests {
    private let video = MockYouTubeClient.makeVideo(videoId: "test-video")

    private func option(_ id: String, selected: Bool) -> AddToPlaylistOption {
        AddToPlaylistOption(playlistId: id, title: id, subtitle: nil, thumbnailURL: nil, isSelected: selected, privacyStatus: nil)
    }

    @Test("Picking a checked playlist removes the video; an unchecked one adds it; checkmarks follow")
    func togglesMembership() async {
        let client = MockYouTubeClient()
        client.addToPlaylistMenu = AddToPlaylistMenu(
            title: nil,
            options: [self.option("WL", selected: false), self.option("PLin", selected: true), self.option("PLout", selected: false)],
            canCreatePlaylist: false
        )
        let membership = YouTubePlaylistMembership(actions: YouTubeVideoActions(client: client))

        await membership.load(for: self.video)
        #expect(membership.options?.map(\.playlistId) == ["PLin", "PLout"])

        if let checked = membership.options?.first {
            await membership.toggle(checked, for: self.video)
        }
        if let unchecked = membership.options?.last {
            await membership.toggle(unchecked, for: self.video)
        }

        #expect(client.playlistRemovals.map(\.playlistId) == ["PLin"])
        #expect(client.playlistAdds.map(\.playlistId) == ["PLout"])
        #expect(membership.options?.map(\.isSelected) == [false, true])
    }

    @Test("Another video starts with a fresh list")
    func resetsForAnotherVideo() async {
        let client = MockYouTubeClient()
        client.addToPlaylistMenu = AddToPlaylistMenu(title: nil, options: [self.option("PLin", selected: true)], canCreatePlaylist: false)
        let membership = YouTubePlaylistMembership(actions: YouTubeVideoActions(client: client))
        await membership.load(for: self.video)

        client.error = YTMusicError.apiError(message: "mock failure", code: nil)
        await membership.load(for: MockYouTubeClient.makeVideo(videoId: "next-video"))

        #expect(membership.videoId == "next-video")
        #expect(membership.options == nil)
        #expect(membership.didFail)
    }

    @Test("Watch Later and playlists in the Save dialog are editable; Liked Videos and others aren't")
    func editablePlaylists() async {
        let client = MockYouTubeClient()
        client.addToPlaylistMenu = AddToPlaylistMenu(title: nil, options: [self.option("PLmine", selected: false)], canCreatePlaylist: false)
        let actions = YouTubeVideoActions(client: client)

        let watchLater = await actions.canEditPlaylist("WL", sampleVideo: self.video)
        let liked = await actions.canEditPlaylist("LL", sampleVideo: self.video)
        let mine = await actions.canEditPlaylist("PLmine", sampleVideo: self.video)
        let saved = await actions.canEditPlaylist("PLsomeoneElse", sampleVideo: self.video)

        #expect(watchLater)
        #expect(!liked)
        #expect(mine)
        #expect(!saved)
    }
}

// MARK: - YouTubePlaylistViewModelRemovalTests

@Suite("YouTubePlaylistViewModel removal", .serialized, .tags(.viewModel))
@MainActor
struct YouTubePlaylistViewModelRemovalTests {
    private func loadedModel() async -> (YouTubePlaylistViewModel, [YouTubeVideo]) {
        let client = MockYouTubeClient()
        let videos = MockYouTubeClient.makeVideos(count: 3)
        client.playlistDetail = YouTubePlaylistDetail(
            playlist: YouTubePlaylist(
                playlistId: "PLtest", title: "Test", channelName: nil, videoCountText: nil, thumbnailURL: nil, firstVideoId: nil
            ),
            videos: videos
        )
        let model = YouTubePlaylistViewModel(playlistId: "PLtest", client: client)
        await model.load()
        return (model, videos)
    }

    @Test("A removed video leaves the page at once and stays gone when YouTube accepts it")
    func removes() async {
        let (model, videos) = await self.loadedModel()
        await model.removeVideo(videos[1]) { _ in true }
        #expect(model.detail?.videos.map(\.videoId) == ["video-0", "video-2"])
    }

    @Test("A refused removal puts the video back")
    func restores() async {
        let (model, videos) = await self.loadedModel()
        await model.removeVideo(videos[1]) { _ in false }
        #expect(model.detail?.videos.map(\.videoId) == ["video-0", "video-1", "video-2"])
    }
}

// MARK: - YouTubePlaylistRemovalRaceTests

@Suite("YouTubePlaylistViewModel concurrent removals", .serialized, .tags(.viewModel))
@MainActor
struct YouTubePlaylistRemovalRaceTests {
    @Test("A failed removal brings back only its video, at its place")
    func restoresOnlyTheFailedVideo() async {
        let client = MockYouTubeClient()
        let videos = MockYouTubeClient.makeVideos(count: 3)
        client.playlistDetail = YouTubePlaylistDetail(
            playlist: YouTubePlaylist(playlistId: "PLtest", title: "Test"),
            videos: videos
        )
        let model = YouTubePlaylistViewModel(playlistId: "PLtest", client: client)
        await model.load()

        // B's removal succeeds while A's is still pending; then A fails.
        await model.removeVideo(videos[0]) { _ in
            await model.removeVideo(videos[1]) { _ in true }
            return false
        }

        #expect(model.detail?.videos.map(\.videoId) == ["video-0", "video-2"])
    }
}
