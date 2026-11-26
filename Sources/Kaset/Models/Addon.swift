import Foundation

// MARK: - Addon

/// An extension Kaset offers in Settings → Extensions → Addons. Nothing of it
/// ships with the app: its files come from the project's own GitHub releases
/// only when the user installs it, and removing it deletes them and the data
/// it kept, leaving Kaset as it was.
enum Addon: String, CaseIterable, Identifiable {
    case adBlocker
    case sponsorBlock

    var id: String {
        self.rawValue
    }

    /// The project's own name.
    var name: String {
        switch self {
        case .adBlocker: "uBlock Origin Lite"
        case .sponsorBlock: "SponsorBlock"
        }
    }

    var summary: String {
        switch self {
        case .adBlocker: String(localized: "Blocks ads and trackers in the video player.")
        case .sponsorBlock: String(localized: "Skips sponsors and other segments the community marked.")
        }
    }

    var systemImage: String {
        switch self {
        case .adBlocker: "shield.lefthalf.filled"
        case .sponsorBlock: "forward.frame"
        }
    }

    /// The GitHub repository whose latest release carries the build.
    var repository: String {
        switch self {
        case .adBlocker: "uBlockOrigin/uBOL-home"
        case .sponsorBlock: "ajayyy/SponsorBlock"
        }
    }

    var projectURL: URL? {
        URL(string: "https://github.com/\(self.repository)")
    }

    /// Whether a release asset is the project's Safari (WebKit) build.
    func isBuild(named assetName: String) -> Bool {
        switch self {
        case .adBlocker: assetName.hasPrefix("uBOLite_") && assetName.hasSuffix(".safari.zip")
        case .sponsorBlock: assetName == "SafariExtension.zip"
        }
    }
}
