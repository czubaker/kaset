import Foundation
import Testing
@testable import Kaset

// MARK: - PlayerBarToolbarTests

/// The window toolbar as one more area of the player bar layout.
@Suite(.serialized)
struct PlayerBarToolbarTests {
    private typealias Music = PlayerBarConfiguration<MusicPlayerBarItem>
    private typealias YouTube = PlayerBarConfiguration<YouTubePlayerBarItem>

    @Test("The standard layouts keep the toolbar as it was")
    func standardToolbar() {
        #expect(Music.standard.items(in: .toolbar) == [.commandBar])
        #expect(YouTube.standard.items(in: .toolbar) == [.refresh, .notifications])
    }

    @Test("A layout saved before the toolbar was part of it gets the standard toolbar; an emptied one stays empty")
    func decodesMissingToolbar() throws {
        let saved = #"{"leading":["artwork"],"center":["playPause"],"trailing":["lyrics"],"settingsMenu":[]}"#
        let old = try JSONDecoder().decode(Music.self, from: Data(saved.utf8))
        #expect(old.items(in: .toolbar) == [.commandBar])
        #expect(old.items(in: .center) == [.playPause])

        let emptied = #"{"leading":[],"center":[],"trailing":[],"settingsMenu":[],"toolbar":[]}"#
        #expect(try JSONDecoder().decode(Music.self, from: Data(emptied.utf8)).items(in: .toolbar).isEmpty)

        var layout = YouTube.standard
        layout.add(.playPause, to: .toolbar, at: 0)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(YouTube.self, from: data) == layout)
    }

    @Test("Buttons move between the bar and the toolbar; details blocks and window buttons stay where they belong")
    func placementRules() {
        var music = Music.standard
        let movedUp = music.add(.playPause, to: .toolbar)
        #expect(movedUp)
        #expect(music.items(in: .toolbar) == [.commandBar, .playPause])
        #expect(!music.items(in: .center).contains(.playPause))
        #expect(music.contains(.playPause) && !music.isOnBar(.playPause))

        let artworkUp = music.add(.artwork, to: .toolbar)
        let mixTracksUp = music.add(.mixTracks, to: .toolbar)
        let commandBarDown = music.add(.commandBar, to: .center)
        #expect(!artworkUp && !mixTracksUp && !commandBarDown)
        #expect(music.items(in: .toolbar).contains(.commandBar))

        var youtube = YouTube.standard
        let floatOnTopUp = youtube.add(.floatOnTop, to: .toolbar)
        let refreshDown = youtube.add(.refresh, to: .trailing)
        #expect(!floatOnTopUp && !refreshDown)
        let captionsUp = youtube.add(.captions, to: .toolbar)
        youtube.add(.flexibleSpace, to: .toolbar)
        youtube.add(.flexibleSpace, to: .toolbar)
        #expect(captionsUp)
        #expect(youtube.items(in: .toolbar).filter { $0 == .flexibleSpace }.count == 2)
    }

    @Test("The watch page's Hide What the Player Bar Shows ignores the toolbar")
    func watchPageIgnoresToolbar() {
        var bar = YouTube.standard
        bar.add(.subscribeIcon, to: .toolbar)
        let layout = YouTubeWatchPageLayout(hiddenElements: [], hidesPlayerBarItems: true)
        #expect(layout.shows(.subscribeButton, playerBar: bar, details: .standard))

        bar.add(.subscribeIcon, to: .trailing)
        #expect(!layout.shows(.subscribeButton, playerBar: bar, details: .standard))
    }
}
