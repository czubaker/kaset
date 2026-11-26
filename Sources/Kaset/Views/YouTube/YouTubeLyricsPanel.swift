import SwiftUI

// MARK: - YouTubeLyricsPanel

/// The song's lyrics beside a music video, from LRCLib: synced lines follow
/// the video and seek it when clicked. Looked up when asked, or for every
/// video with Find Automatically on. Adapted from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
struct YouTubeLyricsPanel: View {
    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @Bindable private var settings = SettingsManager.shared
    let title: String
    let channelName: String?
    /// The length YouTube lists for the video, until the player reports one.
    private let listedDuration: TimeInterval?

    @State private var model: YouTubeLyricsViewModel
    @State private var searchText = ""

    init(video: YouTubeVideo, title: String, channelName: String?) {
        self.title = title
        self.channelName = channelName
        self.listedDuration = video.lengthText.flatMap(YouTubeLyricsPanel.seconds(fromLength:))
        _model = State(initialValue: YouTubeLyricsViewModel(videoId: video.videoId, title: title, channelName: channelName))
    }

    /// "3:33" or "1:02:03" in seconds.
    static func seconds(fromLength text: String) -> TimeInterval? {
        let parts = text.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard (2 ... 3).contains(parts.count), !parts.contains(nil) else { return nil }
        return TimeInterval(parts.compactMap(\.self).reduce(0) { $0 * 60 + $1 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Lyrics", comment: "Header of the lyrics panel beside a YouTube video")
                    .font(.headline)
                Spacer(minLength: 8)
                if self.model.state == .searching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            self.content
        }
        .frame(height: self.isShowingLyrics ? 420 : nil)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .onChange(of: "\(self.title)|\(self.channelName ?? "")", initial: true) {
            self.model.updateQuery(title: self.title, channelName: self.channelName)
        }
        // Looks up by itself only once the video's length is known, so the
        // length check can turn away songs that aren't this video.
        .task(id: "\(self.settings.youtubeLyricsAutoFind)|\(self.duration != nil)") {
            if self.settings.youtubeLyricsAutoFind, self.model.state == .idle, let duration = self.duration {
                self.model.find(duration: duration)
            }
        }
        .onDisappear {
            self.model.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self.model.state {
        case .idle:
            VStack(alignment: .leading, spacing: 10) {
                Button(String(localized: "Find Lyrics")) {
                    self.model.find(duration: self.duration)
                }
                .controlSize(.small)
                self.autoFindToggle
            }
            .padding(12)
        case .searching:
            self.note(String(localized: "Looking for “\(self.model.query.text)” on LRCLib…"))
                .padding(12)
        case let .found(match):
            self.lyrics(match)
        case .notFound, .failed, .editing:
            VStack(alignment: .leading, spacing: 10) {
                if self.model.state == .failed {
                    self.note(String(localized: "Couldn’t reach LRCLib."))
                } else if self.model.state == .notFound {
                    self.note(String(localized: "No lyrics found for “\(self.model.query.text)”."))
                }
                self.searchField
                self.autoFindToggle
            }
            .padding(12)
        }
    }

    private func lyrics(_ match: YouTubeLyricsLookup.Match) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch match.lyrics {
            case let .synced(synced):
                YouTubeSyncedLyrics(lyrics: synced, videoId: self.model.videoId)
            case let .plain(plain):
                ScrollView {
                    Text(plain.text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            case .unavailable:
                EmptyView()
            }

            Divider()
            HStack(spacing: 6) {
                Text(self.matchTitle(match))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    Button(String(localized: "Search Again…")) {
                        self.searchText = self.model.query.text
                        self.model.showSearch()
                    }
                    Toggle(String(localized: "Find Automatically"), isOn: self.$settings.youtubeLyricsAutoFind)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(String(localized: "Lyrics Options"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var searchField: some View {
        TextField(String(localized: "Artist and song"), text: self.$searchText)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .onSubmit {
                self.model.search(self.searchText, duration: self.duration)
            }
            .onAppear {
                if self.searchText.isEmpty {
                    self.searchText = self.model.query.text
                }
            }
    }

    private var autoFindToggle: some View {
        Toggle(String(localized: "Find Automatically"), isOn: self.$settings.youtubeLyricsAutoFind)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .help(String(localized: "Look up lyrics on LRCLib for every video you open."))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func matchTitle(_ match: YouTubeLyricsLookup.Match) -> String {
        let song = [match.artistName, match.trackName].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " — ")
        return String(localized: "\(song) · LRCLib")
    }

    private var isShowingLyrics: Bool {
        if case .found = self.model.state {
            return true
        }
        return false
    }

    /// The video's length, so a song of another length isn't taken for it:
    /// the player's while it plays this video, else the listed one.
    private var duration: TimeInterval? {
        if self.youtubePlayer.currentVideo?.videoId == self.model.videoId, self.youtubePlayer.duration > 0 {
            return self.youtubePlayer.duration
        }
        return self.listedDuration
    }
}

// MARK: - YouTubeSyncedLyrics

/// Synced lines following the video; only this part redraws as it plays.
private struct YouTubeSyncedLyrics: View {
    let lyrics: SyncedLyrics
    let videoId: String

    @Environment(YouTubePlayerService.self) private var youtubePlayer

    var body: some View {
        let timeMs = self.timeMs
        SyncedLyricsDisplayView(
            lyrics: self.lyrics,
            currentLineIndex: timeMs.flatMap { self.lyrics.currentLineIndex(at: $0) },
            displayTimeMs: timeMs,
            onSeek: { lineMs in
                guard self.youtubePlayer.currentVideo?.videoId == self.videoId else { return }
                self.youtubePlayer.seek(to: Double(lineMs) / 1000)
            }
        )
    }

    private var timeMs: Int? {
        guard self.youtubePlayer.currentVideo?.videoId == self.videoId else { return nil }
        return Int(self.youtubePlayer.progress * 1000)
    }
}
