import Foundation

private let barAreas: Set<PlayerBarArea> = [.leading, .center, .trailing]
/// Media details blocks are two lines tall, so they can't sit in the row
/// above the timeline.
private let sideAreas: Set<PlayerBarArea> = [.leading, .trailing]

// MARK: - MusicPlayerBarItem

/// Items of the YouTube Music player bar.
enum MusicPlayerBarItem: String, PlayerBarItemKind {
    case artwork
    case songInfo
    case like
    case dislike
    case mixTracks
    case airPlay
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case volume
    case lyrics
    case queue
    case video
    case miniPlayer
    case space
    case flexibleSpace

    var title: String {
        switch self {
        case .artwork: String(localized: "Artwork")
        case .songInfo: String(localized: "Title and Artist")
        case .like: String(localized: "Like")
        case .dislike: String(localized: "Dislike")
        case .mixTracks: String(localized: "Mix tracks")
        case .airPlay: String(localized: "AirPlay")
        case .shuffle: String(localized: "Shuffle")
        case .previous: String(localized: "Previous track")
        case .playPause: String(localized: "Play/Pause")
        case .next: String(localized: "Next track")
        case .repeatMode: String(localized: "Repeat")
        case .volume: String(localized: "Volume")
        case .lyrics: String(localized: "Lyrics")
        case .queue: String(localized: "Queue")
        case .video: String(localized: "Video")
        case .miniPlayer: String(localized: "Mini Player")
        case .space: String(localized: "Space")
        case .flexibleSpace: String(localized: "Flexible Space")
        }
    }

    var systemImage: String {
        switch self {
        case .artwork: "photo"
        case .songInfo: "music.note"
        case .like: "hand.thumbsup"
        case .dislike: "hand.thumbsdown"
        case .mixTracks: "list.number"
        case .airPlay: "airplayaudio"
        case .shuffle: "shuffle"
        case .previous: "backward.fill"
        case .playPause: "playpause.fill"
        case .next: "forward.fill"
        case .repeatMode: "repeat"
        case .volume: "speaker.wave.2.fill"
        case .lyrics: "quote.bubble"
        case .queue: "list.bullet"
        case .video: "pip.enter"
        case .miniPlayer: "rectangle.inset.bottomright.filled"
        case .space: "square.dashed"
        case .flexibleSpace: "arrow.left.and.right"
        }
    }

    var allowedAreas: Set<PlayerBarArea> {
        switch self {
        case .artwork, .songInfo: sideAreas
        default: barAreas
        }
    }

    var isRepeatable: Bool {
        self == .space || self == .flexibleSpace
    }
}

// MARK: - YouTubePlayerBarItem

/// Items of the YouTube player bar.
enum YouTubePlayerBarItem: String, PlayerBarItemKind {
    case thumbnail
    case channelAvatar
    /// Two lines of text, each a detail of the user's choosing.
    case videoInfo
    /// The channel's avatar beside two lines of details.
    case channelInfo
    case subscribe
    case like
    case dislike
    case skipBack
    case playPause
    case skipForward
    case volume
    case fullView
    case watchLater
    case airPlay
    case captions
    case settingsMenu
    case quality
    case playbackSpeed
    case audioTrack
    case floatOnTop
    case pictureInPicture
    case space
    case flexibleSpace

    var title: String {
        switch self {
        case .thumbnail: String(localized: "Thumbnail")
        case .channelAvatar: String(localized: "Channel Avatar")
        case .videoInfo: String(localized: "Details")
        case .channelInfo: String(localized: "Avatar and Details")
        case .subscribe: String(localized: "Subscribe Button")
        case .like: String(localized: "Like")
        case .dislike: String(localized: "Dislike")
        case .skipBack: String(localized: "Back 30 seconds")
        case .playPause: String(localized: "Play/Pause")
        case .skipForward: String(localized: "Forward 30 seconds")
        case .volume: String(localized: "Volume")
        case .fullView: String(localized: "Full view")
        case .watchLater: String(localized: "Watch Later")
        case .airPlay: String(localized: "AirPlay")
        case .captions: String(localized: "Closed captions")
        case .settingsMenu: String(localized: "Video settings")
        case .quality: String(localized: "Video quality")
        case .playbackSpeed: String(localized: "Playback speed")
        case .audioTrack: String(localized: "Audio track")
        case .floatOnTop: String(localized: "Float on Top")
        case .pictureInPicture: String(localized: "Picture in Picture")
        case .space: String(localized: "Space")
        case .flexibleSpace: String(localized: "Flexible Space")
        }
    }

    var systemImage: String {
        switch self {
        case .thumbnail: "photo"
        case .channelAvatar: "person.crop.circle"
        case .videoInfo: "text.alignleft"
        case .channelInfo: "person.text.rectangle"
        case .subscribe: "person.badge.plus"
        case .like: "hand.thumbsup"
        case .dislike: "hand.thumbsdown"
        case .skipBack: "gobackward.30"
        case .playPause: "playpause.fill"
        case .skipForward: "goforward.30"
        case .volume: "speaker.wave.2.fill"
        case .fullView: "arrow.up.left.and.arrow.down.right"
        case .watchLater: "clock"
        case .airPlay: "airplayvideo"
        case .captions: "captions.bubble"
        case .settingsMenu: "gearshape"
        case .quality: "sparkles.tv"
        case .playbackSpeed: "gauge.with.dots.needle.67percent"
        case .audioTrack: "waveform"
        case .floatOnTop: "pin"
        case .pictureInPicture: "pip.enter"
        case .space: "square.dashed"
        case .flexibleSpace: "arrow.left.and.right"
        }
    }

    var allowedAreas: Set<PlayerBarArea> {
        switch self {
        case .thumbnail, .channelAvatar, .videoInfo, .channelInfo, .subscribe:
            sideAreas
        case .captions, .quality, .playbackSpeed, .audioTrack:
            barAreas.union([.settingsMenu])
        default:
            barAreas
        }
    }

    var isRepeatable: Bool {
        self == .space || self == .flexibleSpace
    }

    /// Whether the item is a details block whose two lines the user picks.
    var hasDetailLines: Bool {
        self == .videoInfo || self == .channelInfo
    }
}

// MARK: - Defaults

extension PlayerBarConfiguration where Item == MusicPlayerBarItem {
    /// The bar as it shipped before it was customizable.
    static var standard: Self {
        Self(
            leading: [.artwork, .songInfo, .like, .dislike],
            center: [.mixTracks, .airPlay, .shuffle, .previous, .playPause, .next, .repeatMode, .volume],
            trailing: [.lyrics, .queue, .video, .miniPlayer]
        )
    }
}

extension PlayerBarConfiguration where Item == YouTubePlayerBarItem {
    /// The bar as it shipped before it was customizable.
    static var standard: Self {
        Self(
            leading: [.thumbnail, .videoInfo, .like, .dislike],
            center: [.skipBack, .playPause, .skipForward, .volume],
            trailing: [.fullView, .watchLater, .airPlay, .captions, .settingsMenu, .floatOnTop, .pictureInPicture],
            settingsMenu: [.audioTrack, .playbackSpeed, .quality]
        )
    }
}
