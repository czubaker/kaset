import Foundation

// MARK: - ChannelNotificationPreference

/// The notification bell next to Subscribe for a channel the account follows.
/// Its options, their labels (in the account's language), and the opaque
/// `params` that apply them come from YouTube's `notificationPreferenceButton`
/// menu, so the current choice is the server's and a change replays YouTube's
/// own `modifyChannelNotificationPreferenceEndpoint`. Ported from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
struct ChannelNotificationPreference: Hashable {
    /// What the bell sends: named for what the user gets, not YouTube's icons.
    enum Level: Hashable {
        case all
        case personalized
        case none
        case unknown

        init(iconType: String) {
            switch iconType {
            case "NOTIFICATIONS_ACTIVE": self = .all
            case "NOTIFICATIONS_NONE": self = .personalized
            case "NOTIFICATIONS_OFF": self = .none
            default: self = .unknown
            }
        }

        var symbolName: String {
            switch self {
            case .all: "bell.and.waves.left.and.right.fill"
            case .personalized: "bell.fill"
            case .none: "bell.slash"
            case .unknown: "bell"
            }
        }
    }

    struct Option: Hashable, Identifiable {
        let level: Level
        let label: String
        /// Posted to `notification/modify_channel_preference`.
        let params: String
        let isCurrent: Bool

        var id: String {
            self.params
        }
    }

    let channelId: String
    let options: [Option]

    var current: Option? {
        self.options.first(where: \.isCurrent)
    }

    var currentLevel: Level {
        self.current?.level ?? .unknown
    }

    /// The same menu with `option` as the current choice.
    func selecting(_ option: Option) -> Self {
        Self(
            channelId: self.channelId,
            options: self.options.map {
                Option(level: $0.level, label: $0.label, params: $0.params, isCurrent: $0.id == option.id)
            }
        )
    }
}
