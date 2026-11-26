import Foundation
import Testing
@testable import Kaset

// MARK: - SleepTimerTests

@Suite(.serialized)
@MainActor
struct SleepTimerTests {
    private final class Player {
        var playing: SleepTimer.NowPlaying?
        var pauses = 0
    }

    private static func makeTimer(_ player: Player) -> SleepTimer {
        let timer = SleepTimer()
        timer.pausePlayback = { player.pauses += 1 }
        timer.nowPlaying = { player.playing }
        return timer
    }

    private static func playing(_ id: String, at progress: TimeInterval, of duration: TimeInterval) -> SleepTimer.NowPlaying {
        SleepTimer.NowPlaying(id: id, progress: progress, duration: duration, isPlaying: true, isVideo: false)
    }

    @Test("A timed setting counts down and pauses once at its deadline")
    func pausesAtDeadline() {
        let player = Player()
        let timer = Self.makeTimer(player)
        let start = Date(timeIntervalSince1970: 1000)
        timer.start(.minutes(15), now: start)
        defer { timer.cancel() }

        timer.tick(now: start.addingTimeInterval(60))
        #expect(timer.remaining == TimeInterval(14 * 60))
        #expect(player.pauses == 0)

        timer.tick(now: start.addingTimeInterval(15 * 60))
        #expect(player.pauses == 1)
        #expect(!timer.isActive)

        timer.tick(now: start.addingTimeInterval(16 * 60))
        #expect(player.pauses == 1)
    }

    @Test("End of track pauses as the item ends, or when the next one has already started")
    func pausesAtEndOfItem() {
        let player = Player()
        player.playing = Self.playing("a", at: 10, of: 200)
        let timer = Self.makeTimer(player)
        timer.start(.endOfItem)
        defer { timer.cancel() }

        timer.tick()
        #expect(player.pauses == 0)
        player.playing = Self.playing("a", at: 199.5, of: 200)
        timer.tick()
        #expect(player.pauses == 1)
        #expect(!timer.isActive)

        // Skipped past the last second between looks: the next one is paused.
        player.playing = Self.playing("b", at: 5, of: 180)
        timer.start(.endOfItem)
        player.playing = Self.playing("b", at: 177, of: 180)
        timer.tick()
        player.playing = Self.playing("c", at: 0.5, of: 240)
        timer.tick()
        #expect(player.pauses == 2)
    }

    @Test("Picking another item mid-way waits for that one to end instead")
    func userSkipRearms() {
        let player = Player()
        player.playing = Self.playing("a", at: 30, of: 200)
        let timer = Self.makeTimer(player)
        timer.start(.endOfItem)
        defer { timer.cancel() }

        timer.tick()
        player.playing = Self.playing("b", at: 1, of: 300)
        timer.tick()
        #expect(player.pauses == 0)
        #expect(timer.isActive)

        player.playing = Self.playing("b", at: 299.5, of: 300)
        timer.tick()
        #expect(player.pauses == 1)
    }

    @Test("When the next item is still loading, End of track pauses it once it plays")
    func waitsForNextItemToPlay() {
        let player = Player()
        player.playing = Self.playing("a", at: 197, of: 200)
        let timer = Self.makeTimer(player)
        timer.start(.endOfItem)
        defer { timer.cancel() }

        timer.tick()
        player.playing = SleepTimer.NowPlaying(id: "b", progress: 0, duration: 0, isPlaying: false, isVideo: true)
        timer.tick()
        #expect(player.pauses == 0)
        #expect(timer.isActive)

        player.playing = Self.playing("b", at: 0.5, of: 300)
        timer.tick()
        #expect(player.pauses == 1)
        #expect(!timer.isActive)
    }

    @Test("An item that played to its end with nothing after it turns the timer off")
    func endsWithNothingNext() {
        let player = Player()
        player.playing = Self.playing("a", at: 190, of: 200)
        let timer = Self.makeTimer(player)
        timer.start(.endOfItem)
        timer.tick()
        player.playing = SleepTimer.NowPlaying(id: "a", progress: 200, duration: 200, isPlaying: false, isVideo: true)
        timer.tick()
        #expect(player.pauses == 0)
        #expect(!timer.isActive)
    }

    @Test("An ad's end isn't the video's end")
    func ignoresAds() {
        let player = Player()
        player.playing = Self.playing("a", at: 10, of: 200)
        let timer = Self.makeTimer(player)
        timer.start(.endOfItem)
        defer { timer.cancel() }

        player.playing = SleepTimer.NowPlaying(id: "a", progress: 14.5, duration: 15, isPlaying: true, isVideo: true, isAd: true)
        timer.tick()
        #expect(player.pauses == 0)
        player.playing = Self.playing("a", at: 199.5, of: 200)
        timer.tick()
        #expect(player.pauses == 1)
    }

    @Test("Started with nothing playing, End of track waits for what plays next to end")
    func endOfItemWithNothingPlaying() {
        let player = Player()
        let timer = Self.makeTimer(player)
        timer.start(.endOfItem)
        defer { timer.cancel() }

        player.playing = Self.playing("a", at: 0, of: 200)
        timer.tick()
        timer.tick()
        #expect(player.pauses == 0)
        player.playing = Self.playing("a", at: 199.9, of: 200)
        timer.tick()
        #expect(player.pauses == 1)
    }

    @Test("Turning it off stops it without pausing")
    func cancel() {
        let player = Player()
        let timer = Self.makeTimer(player)
        let start = Date()
        timer.start(.minutes(30), now: start)
        timer.cancel()
        timer.tick(now: start.addingTimeInterval(31 * 60))
        #expect(player.pauses == 0)
        #expect(timer.setting == nil && timer.remaining == nil)
    }

    @Test("Time left reads as minutes and seconds, or hours past one")
    func formatsRemaining() {
        #expect(SleepTimer.formatted(754) == "12:34")
        #expect(SleepTimer.formatted(59.2) == "1:00")
        #expect(SleepTimer.formatted(3723) == "1:02:03")
    }
}
