import Foundation
import Testing
@testable import Kaset

@Suite("PlayerBarConfiguration", .tags(.model))
struct PlayerBarConfigurationTests {
    private typealias Music = PlayerBarConfiguration<MusicPlayerBarItem>
    private typealias YouTube = PlayerBarConfiguration<YouTubePlayerBarItem>

    @Test("The standard layouts are the bars as they shipped")
    func standardLayouts() {
        #expect(Music.standard.items(in: .leading) == [.artwork, .songInfo, .like, .dislike])
        #expect(Music.standard.items(in: .center) == [.mixTracks, .airPlay, .shuffle, .previous, .playPause, .next, .repeatMode, .volume])
        #expect(Music.standard.items(in: .trailing) == [.lyrics, .queue, .video, .miniPlayer])
        #expect(Music.standard.items(in: .settingsMenu).isEmpty)

        #expect(YouTube.standard.items(in: .leading) == [.thumbnail, .videoInfo, .like, .dislike])
        #expect(YouTube.standard.items(in: .center) == [.skipBack, .playPause, .skipForward, .volume])
        #expect(YouTube.standard.items(in: .trailing) == [
            .fullView, .watchLater, .airPlay, .captions, .settingsMenu, .floatOnTop, .pictureInPicture,
        ])
        #expect(YouTube.standard.items(in: .settingsMenu) == [.audioTrack, .playbackSpeed, .quality])
    }

    @Test("Building drops repeats and items in areas they can't sit in, but keeps repeated spaces")
    func initSanitizes() {
        let layout = YouTube(
            leading: [.thumbnail, .thumbnail, .space],
            center: [.videoInfo, .playPause, .space, .space],
            trailing: [.playPause],
            settingsMenu: [.fullView, .quality]
        )

        #expect(layout.items(in: .leading) == [.thumbnail, .space])
        // The title block can't sit above the timeline.
        #expect(layout.items(in: .center) == [.playPause, .space, .space])
        #expect(layout.items(in: .trailing).isEmpty)
        // Only the pickers can go in the settings menu.
        #expect(layout.items(in: .settingsMenu) == [.quality])
    }

    @Test("Adding an item that's already placed moves it; adding a space adds another")
    func addMovesOrRepeats() {
        var layout = Music.standard

        let changed1 = layout.add(.lyrics, to: .leading, at: 0)
        #expect(changed1)
        #expect(layout.items(in: .leading).first == .lyrics)
        #expect(!layout.items(in: .trailing).contains(.lyrics))

        let changed2 = layout.add(.space, to: .trailing)
        #expect(changed2)
        let changed3 = layout.add(.space, to: .trailing, at: 0)
        #expect(changed3)
        #expect(layout.items(in: .trailing) == [.space, .queue, .video, .miniPlayer, .space])
    }

    @Test("An item can't be added or moved where it isn't allowed")
    func disallowedAreasRefused() {
        var layout = Music.standard

        let changed4 = layout.add(.artwork, to: .center)
        #expect(!changed4)
        let changed5 = layout.move(from: .leading, at: 0, to: .center)
        #expect(!changed5)
        let changed6 = layout.add(.lyrics, to: .settingsMenu)
        #expect(!changed6)
        #expect(layout == Music.standard)
    }

    @Test("Moving within an area lands before the item at the target index")
    func moveWithinArea() {
        var layout = Music.standard

        // shuffle (2) before next (5): after taking it out, next sits at 4.
        let changed7 = layout.move(from: .center, at: 2, to: .center, at: 5)
        #expect(changed7)
        #expect(layout.items(in: .center) == [.mixTracks, .airPlay, .previous, .playPause, .shuffle, .next, .repeatMode, .volume])

        // And back to the front.
        let changed8 = layout.move(from: .center, at: 4, to: .center, at: 0)
        #expect(changed8)
        #expect(layout.items(in: .center).first == .shuffle)

        // A missing source index changes nothing.
        let changed9 = layout.move(from: .center, at: 99, to: .center, at: 0)
        #expect(!changed9)
    }

    @Test("Moving across areas, and into and out of the settings menu")
    func moveAcrossAreas() {
        var layout = YouTube.standard

        let changed10 = layout.move(from: .settingsMenu, at: 1, to: .trailing, at: 0)
        #expect(changed10)
        #expect(layout.items(in: .trailing).first == .playbackSpeed)
        #expect(layout.items(in: .settingsMenu) == [.audioTrack, .quality])

        let changed11 = layout.move(from: .trailing, at: 4, to: .settingsMenu, at: 0)
        #expect(changed11)
        #expect(layout.items(in: .settingsMenu).first == .captions)
    }

    @Test("Removing by position takes off one item, a single space among repeats")
    func removeByPosition() {
        var layout = Music(leading: [.artwork], center: [.space, .playPause, .space], trailing: [])

        layout.remove(from: .center, at: 2)
        #expect(layout.items(in: .center) == [.space, .playPause])
        layout.remove(from: .center, at: 9)
        #expect(layout.items(in: .center) == [.space, .playPause])
    }

    @Test("The palette offers what's not placed, and spaces always")
    func paletteItems() {
        let layout = Music.standard
        #expect(layout.paletteItems == [.sleepTimer, .customize, .space, .flexibleSpace])

        var trimmed = layout
        trimmed.remove(from: .trailing, at: 3)
        #expect(trimmed.paletteItems == [.miniPlayer, .sleepTimer, .customize, .space, .flexibleSpace])
    }

    @Test("A layout survives encoding, and unknown items from other versions are dropped")
    func codableRoundTrip() throws {
        var layout = YouTube.standard
        layout.add(.channelInfo, to: .leading, at: 0)
        layout.add(.flexibleSpace, to: .center, at: 0)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(YouTube.self, from: data) == layout)

        let fromLater = Data(#"{"leading":["thumbnail","hologram"],"center":["playPause"],"trailing":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(YouTube.self, from: fromLater)
        #expect(decoded.items(in: .leading) == [.thumbnail])
        #expect(decoded.items(in: .center) == [.playPause])
        #expect(decoded.items(in: .settingsMenu).isEmpty)
    }

    @Test("Row items keep their identity when an earlier item hides, and repeated spaces stay distinct")
    func rowIdentityFollowsItems() {
        typealias RowID = PlayerBarRowID<MusicPlayerBarItem>
        let withMix = RowID.ids(for: [.mixTracks, .shuffle, .playPause, .space, .volume, .space])
        let withoutMix = RowID.ids(for: [.shuffle, .playPause, .space, .volume, .space])
        let expectedSpaces = [RowID(item: .space, occurrence: 0), RowID(item: .space, occurrence: 1)]

        #expect(Array(withMix.dropFirst()) == withoutMix)
        #expect(Set(withMix).count == withMix.count)
        #expect(withoutMix.filter { $0.item == .space } == expectedSpaces)
    }
}
