import Foundation

// MARK: - Queue

/// The user's queue of videos: Play Next puts a video at its front, Add to
/// Queue at its end. When a video ends, or Next is pressed, the queue's first
/// video plays before any related one, whether or not Autoplay is on.
extension YouTubePlayerService {
    /// Puts `video` first in the queue.
    func playNext(_ video: YouTubeVideo) {
        guard video.videoId != self.currentVideo?.videoId else { return }
        self.videoQueue.removeAll { $0.videoId == video.videoId }
        self.videoQueue.insert(video, at: 0)
    }

    /// Puts `video` last in the queue.
    func addToQueue(_ video: YouTubeVideo) {
        guard video.videoId != self.currentVideo?.videoId,
              !self.videoQueue.contains(where: { $0.videoId == video.videoId })
        else { return }
        self.videoQueue.append(video)
    }

    func removeFromQueue(atOffsets offsets: IndexSet) {
        self.videoQueue.remove(atOffsets: offsets)
    }

    func moveInQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
        self.videoQueue.move(fromOffsets: source, toOffset: destination)
    }

    func clearQueue() {
        self.videoQueue.removeAll()
    }

    /// Plays the queued video at `index` now; the ones before it stay queued.
    func playFromQueue(at index: Int) {
        guard self.videoQueue.indices.contains(index) else { return }
        let video = self.videoQueue[index]
        self.beginYouTubePlaybackIntent()
        self.advance(to: video)
    }

    /// Plays the queue's first video now (Next). Returns whether there was one.
    func advanceToQueuedVideo() -> Bool {
        guard let next = self.videoQueue.first else { return false }
        self.advance(to: next)
        return true
    }

    /// After `videoId` played to its end, plays the queue's first video, a
    /// moment later so the finish settles first. Returns whether it will.
    func playQueueAfterFinish(of videoId: String?) -> Bool {
        guard let next = self.videoQueue.first else { return false }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, self.currentVideo?.videoId == videoId, !self.isPlaying,
                  self.videoQueue.first?.videoId == next.videoId
            else { return }
            self.advance(to: next)
        }
        return true
    }
}
