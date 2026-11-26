import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubePlaylistSaveTests

/// Saving someone's playlist, with the header shape captured with
/// api-explorer (November 2026); IDs are placeholders.
@Suite(.serialized, .tags(.viewModel))
@MainActor
struct YouTubePlaylistSaveTests {
    private static func page(playlistId: String, toggled: Bool) -> [String: Any] {
        ["header": ["pageHeaderRenderer": ["content": ["pageHeaderViewModel": ["actions": ["flexibleActionsViewModel": [
            "actionsRows": [["actions": [
                ["buttonViewModel": ["iconName": "PLAY_ALL"]],
                ["toggleButtonViewModel": [
                    "isToggled": toggled,
                    "defaultButtonViewModel": ["buttonViewModel": ["iconName": "PLAYLIST_ADD", "onTap": ["innertubeCommand": [
                        "likeEndpoint": ["status": "LIKE", "target": ["playlistId": playlistId]],
                    ]]]],
                ]],
            ]]],
        ]]]]]]]
    }

    @Test("The page says whether the playlist is saved; one without Save says nothing")
    func readsTheSaveState() {
        #expect(YouTubePlaylistPageParser.saveState(of: Self.page(playlistId: "PLmock", toggled: true), playlistId: "VLPLmock") == true)
        #expect(YouTubePlaylistPageParser.saveState(of: Self.page(playlistId: "PLmock", toggled: false), playlistId: "PLmock") == false)
        #expect(YouTubePlaylistPageParser.saveState(of: Self.page(playlistId: "PLother", toggled: true), playlistId: "PLmock") == nil)
        #expect(YouTubePlaylistPageParser.saveState(of: [:], playlistId: "PLmock") == nil)
    }

    @Test("Saving shows at once and goes to YouTube; a refusal puts it back")
    func togglesSaved() async {
        let client = MockYouTubeClient()
        client.playlistDetail = YouTubePlaylistDetail(
            playlist: YouTubePlaylist(playlistId: "PLmock", title: "Mix", channelName: nil, videoCountText: nil, thumbnailURL: nil),
            videos: [],
            isSavedToLibrary: false
        )
        let model = YouTubePlaylistViewModel(playlistId: "PLmock", client: client)
        await model.load()

        await model.toggleSaved()
        #expect(model.detail?.isSavedToLibrary == true)
        #expect(client.playlistSaveChanges.map(\.saved) == [true])

        client.error = URLError(.notConnectedToInternet)
        await model.toggleSaved()
        #expect(model.detail?.isSavedToLibrary == true)
    }
}
