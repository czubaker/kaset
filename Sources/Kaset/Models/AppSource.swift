import Foundation

// MARK: - AppSource

/// The active content source for the app-wide experience.
///
/// Kaset presents two parallel experiences over the same Google login:
/// YouTube Music (the default) and regular YouTube video. The source toggle
/// at the bottom of the sidebar flips between them. Switching sources only
/// swaps the visible surface — playback from the other source continues.
enum AppSource: String, CaseIterable, Identifiable {
    /// The YouTube Music experience (default).
    case music

    /// The regular YouTube video experience.
    case video

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .music:
            String(localized: "Music")
        case .video:
            String(localized: "YouTube")
        }
    }

    /// SF Symbol shown on the source toggle segment.
    var icon: String {
        switch self {
        case .music:
            "music.note"
        case .video:
            "play.rectangle.fill"
        }
    }
}

// MARK: - AppMode

/// Which experiences the app shows: both (the default, with the source
/// toggle), or only one of them, which the app then stays on. Ported in
/// spirit from KasetPlus's YouTube-only mode (github.com/Yoddikko/kasetPlus,
/// MIT), with a YouTube Music-only counterpart.
enum AppMode: String, CaseIterable, Identifiable {
    case both
    case youtubeOnly
    case musicOnly

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .both: String(localized: "YouTube and YouTube Music")
        case .youtubeOnly: String(localized: "YouTube Only")
        case .musicOnly: String(localized: "YouTube Music Only")
        }
    }

    /// The source the app stays on when it shows only one.
    var forcedSource: AppSource? {
        switch self {
        case .both: nil
        case .youtubeOnly: .video
        case .musicOnly: .music
        }
    }

    var showsMusic: Bool {
        self != .youtubeOnly
    }

    var showsYouTube: Bool {
        self != .musicOnly
    }
}
