import Foundation

// MARK: - VideoCollaborator

/// One of the channels credited on a collaboration upload. YouTube shows those
/// with stacked avatars and a "Collaborators" list instead of one channel, each
/// with its own Subscribe button. Ported from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
struct VideoCollaborator: Identifiable, Hashable {
    let channelId: String
    let name: String
    let isVerified: Bool
    /// e.g. "@jubilee".
    let handle: String?
    /// e.g. "11.1M subscribers".
    let subscriberText: String?
    let avatarURL: URL?
    /// Whether the account followed the channel when the page loaded.
    let isSubscribed: Bool

    var id: String {
        self.channelId
    }

    /// The row's second line, e.g. "@jubilee • 11.1M subscribers".
    var detail: String? {
        let parts = [self.handle, self.subscriberText].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
