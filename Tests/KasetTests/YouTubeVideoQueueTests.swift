import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubeVideoQueueTests

@Suite(.serialized)
@MainActor
struct YouTubeVideoQueueTests {
    private let controller: MockYouTubeWatchPlaybackController
    private let sut: YouTubePlayerService

    init() {
        self.controller = MockYouTubeWatchPlaybackController()
        self.sut = YouTubePlayerService(playbackController: self.controller)
    }

    private static func video(_ id: String) -> YouTubeVideo {
        MockYouTubeClient.makeVideo(videoId: id)
    }

    @Test("Play Next goes first, Add to Queue last; no repeats, and not the video playing")
    func ordersQueue() {
        self.sut.play(video: Self.video("now"))
        self.sut.addToQueue(Self.video("a"))
        self.sut.addToQueue(Self.video("b"))
        self.sut.playNext(Self.video("c"))
        self.sut.addToQueue(Self.video("a"))
        self.sut.playNext(Self.video("b"))
        self.sut.addToQueue(Self.video("now"))
        #expect(self.sut.videoQueue.map(\.videoId) == ["b", "c", "a"])

        self.sut.moveInQueue(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(self.sut.videoQueue.map(\.videoId) == ["a", "b", "c"])
        self.sut.removeFromQueue(atOffsets: IndexSet(integer: 1))
        #expect(self.sut.videoQueue.map(\.videoId) == ["a", "c"])
    }

    @Test("Next plays the queue before related videos")
    func nextPlaysQueue() async {
        self.sut.play(video: Self.video("now"))
        self.sut.setUpNext([Self.video("related")])
        self.sut.addToQueue(Self.video("queued"))

        await self.sut.skipForward()
        #expect(self.sut.currentVideo?.videoId == "queued")
        #expect(self.sut.videoQueue.isEmpty)

        await self.sut.skipForward()
        #expect(self.sut.currentVideo?.videoId == "related")
    }

    @Test("A video that ends plays the queue's first, with or without Autoplay")
    func finishPlaysQueue() async throws {
        let occurrence = YouTubePlaybackOccurrence(documentGeneration: 1, mediaGeneration: 1)
        self.sut.play(video: Self.video("now"))
        self.sut.updatePlaybackState(.init(isPlaying: true, progress: 59, duration: 60, videoId: "now", playbackOccurrence: occurrence))
        self.sut.addToQueue(Self.video("queued"))

        self.sut.handleVideoEnded(videoId: "now", playbackOccurrence: occurrence)
        #expect(self.sut.autoplayPendingVideo == nil)
        try await Task.sleep(for: .milliseconds(900))
        #expect(self.sut.currentVideo?.videoId == "queued")
    }

    @Test("Playing a queued video directly takes it off the queue")
    func playingQueuedVideoDequeues() {
        self.sut.play(video: Self.video("now"))
        self.sut.addToQueue(Self.video("a"))
        self.sut.addToQueue(Self.video("b"))
        self.sut.playFromQueue(at: 1)
        #expect(self.sut.currentVideo?.videoId == "b")
        #expect(self.sut.videoQueue.map(\.videoId) == ["a"])
    }
}
