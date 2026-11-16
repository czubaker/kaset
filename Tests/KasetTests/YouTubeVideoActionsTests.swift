import Foundation
import Testing
@testable import Kaset

// MARK: - SaveDialogFixture

/// The `playlist/get_add_to_playlist` shape the YouTube web client receives,
/// verified in November 2026 (titles and IDs are placeholders).
private enum SaveDialogFixture {
    static func option(id: String, title: String, contains: String, privacy: String = "PRIVATE") -> [String: Any] {
        [
            "playlistAddToOptionRenderer": [
                "playlistId": id,
                "title": ["simpleText": title],
                "containsSelectedVideos": contains,
                "privacy": privacy,
                "addToPlaylistServiceEndpoint": [
                    "playlistEditEndpoint": [
                        "playlistId": id,
                        "actions": [["addedVideoId": "test-video", "action": "ACTION_ADD_VIDEO"]],
                    ],
                ],
                "removeFromPlaylistServiceEndpoint": [
                    "playlistEditEndpoint": [
                        "playlistId": id,
                        "actions": [["removedVideoId": "test-video", "action": "ACTION_REMOVE_VIDEO_BY_VIDEO_ID"]],
                    ],
                ],
            ],
        ]
    }

    static var response: [String: Any] {
        ["contents": [[
            "addToPlaylistRenderer": [
                "actions": [[
                    "menuTitleRenderer": ["title": ["runs": [["text": "Save video to..."]]]],
                ]],
                "playlists": [
                    option(id: "WL", title: "Watch later", contains: "NONE"),
                    option(id: "PLsaved", title: "Saved", contains: "ALL", privacy: "PUBLIC"),
                    option(id: "PLother", title: "Other", contains: "NONE"),
                ],
            ],
        ]]]
    }
}

// MARK: - YouTubeSaveDialogParsingTests

@Suite("YouTube save dialog parsing", .tags(.parser))
struct YouTubeSaveDialogParsingTests {
    @Test("Options keep their order and mark playlists that already hold the video")
    func parsesSaveDialog() {
        let menu = PlaylistParser.parseAddToPlaylistMenu(SaveDialogFixture.response)
        let expectedIDs = ["WL", "PLsaved", "PLother"]

        #expect(menu.options.map(\.playlistId) == expectedIDs)
        #expect(menu.options.map(\.isSelected) == [false, true, false])
        #expect(menu.options[1].title == "Saved")
        #expect(menu.options[1].privacyStatus == .public)
        #expect(!menu.canCreatePlaylist)
    }
}

// MARK: - YouTubeVideoActionsTests

@Suite("YouTubeVideoActions", .tags(.viewModel))
@MainActor
struct YouTubeVideoActionsTests {
    private let video = MockYouTubeClient.makeVideo(videoId: "test-video")

    @Test("Adding to Watch Later confirms it")
    func savesToWatchLater() async {
        let client = MockYouTubeClient()
        let actions = YouTubeVideoActions(client: client)

        await actions.saveToWatchLater(self.video)

        #expect(client.watchLaterAdds == ["test-video"])
        #expect(actions.toast?.isError == false)
    }

    @Test("A failed save reports an error")
    func reportsFailedSave() async {
        let client = MockYouTubeClient()
        client.error = YTMusicError.apiError(message: "mock failure", code: nil)
        let actions = YouTubeVideoActions(client: client)

        await actions.saveToWatchLater(self.video)
        #expect(actions.toast?.isError == true)

        let toastID = actions.toast?.id
        let playlist = AddToPlaylistOption(
            playlistId: "PLother", title: "Other", subtitle: nil, thumbnailURL: nil, isSelected: false, privacyStatus: nil
        )
        let added = await actions.addToPlaylist(self.video, playlist: playlist)
        #expect(!added)
        #expect(actions.toast?.isError == true)
        #expect(actions.toast?.id != toastID)
    }

    @Test("Adding to a playlist sends its ID and names it in the confirmation")
    func addsToPlaylist() async {
        let client = MockYouTubeClient()
        let actions = YouTubeVideoActions(client: client)
        let playlist = AddToPlaylistOption(
            playlistId: "PLother", title: "Other", subtitle: nil, thumbnailURL: nil, isSelected: false, privacyStatus: nil
        )

        let added = await actions.addToPlaylist(self.video, playlist: playlist)

        #expect(added)
        #expect(client.playlistAdds.map(\.videoId) == ["test-video"])
        #expect(client.playlistAdds.map(\.playlistId) == ["PLother"])
        #expect(actions.toast?.isError == false)
        #expect(actions.toast?.message.contains("Other") == true)
    }

    @Test("The playlist submenu leaves out Watch Later, which has its own item")
    func playlistOptionsSkipWatchLater() async throws {
        let client = MockYouTubeClient()
        client.addToPlaylistMenu = PlaylistParser.parseAddToPlaylistMenu(SaveDialogFixture.response)
        let actions = YouTubeVideoActions(client: client)

        let options = try await actions.playlistOptions(for: self.video)

        #expect(options.map(\.playlistId) == ["PLsaved", "PLother"])
    }

    @Test("Dismissing an old toast keeps a newer one")
    func clearsOnlyMatchingToast() async {
        let actions = YouTubeVideoActions(client: MockYouTubeClient())
        await actions.saveToWatchLater(self.video)
        let first = actions.toast?.id
        await actions.saveToWatchLater(self.video)

        if let first {
            actions.clearToast(id: first)
        }
        #expect(actions.toast != nil)
        if let current = actions.toast?.id {
            actions.clearToast(id: current)
        }
        #expect(actions.toast == nil)
    }
}
