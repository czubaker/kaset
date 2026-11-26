import SwiftUI
import Testing
@testable import Kaset

// MARK: - AppModeAndAccentTests

@Suite(.serialized, .tags(.service))
@MainActor
struct AppModeAndAccentTests {
    @Test("Each mode keeps the app on the one experience it shows")
    func modesForceTheirSource() {
        #expect(AppMode.both.forcedSource == nil)
        #expect(AppMode.youtubeOnly.forcedSource == .video)
        #expect(AppMode.musicOnly.forcedSource == .music)
        #expect(AppMode.youtubeOnly.showsYouTube && !AppMode.youtubeOnly.showsMusic)
        #expect(AppMode.musicOnly.showsMusic && !AppMode.musicOnly.showsYouTube)
    }

    @Test("Switching to a one-experience mode moves the app there and keeps it there")
    func modeChangesMoveTheSource() {
        let settings = SettingsManager.shared
        let previousMode = settings.appMode
        let previousSource = settings.appSource
        defer {
            settings.appMode = previousMode
            settings.appSource = previousSource
        }

        settings.appMode = .both
        settings.appSource = .music
        settings.appMode = .youtubeOnly
        #expect(settings.appSource == .video)
        settings.appSource = .music
        #expect(settings.appSource == .video)

        settings.appMode = .musicOnly
        #expect(settings.appSource == .music)

        settings.appMode = .both
        settings.appSource = .video
        #expect(settings.appSource == .video)
    }

    @Test("An unknown saved mode falls back to both")
    func loadsModesLeniently() throws {
        let suite = "AppModeAndAccentTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SettingsManager.loadAppMode(from: defaults) == .both)
        defaults.set("musicOnly", forKey: SettingsManager.Keys.appMode)
        #expect(SettingsManager.loadAppMode(from: defaults) == .musicOnly)
        defaults.set("someday", forKey: SettingsManager.Keys.appMode)
        #expect(SettingsManager.loadAppMode(from: defaults) == .both)
    }

    @Test("Accent colors round-trip through #RRGGBB, and bad values are ignored")
    func accentHexRoundTrips() throws {
        let color = try #require(SettingsManager.color(fromHex: "#1E90FF"))
        #expect(SettingsManager.hex(from: color) == "#1E90FF")
        #expect(SettingsManager.color(fromHex: "1E90FF") != nil)
        #expect(SettingsManager.color(fromHex: "#12345") == nil)
        #expect(SettingsManager.color(fromHex: "#GGGGGG") == nil)
    }

    @Test("Picking the brand color again forgets the custom accent")
    func resetForgetsTheCustomAccent() throws {
        let settings = SettingsManager.shared
        let previous = settings.accentColor
        defer { settings.accentColor = previous }

        settings.accentColor = try #require(SettingsManager.color(fromHex: "#1E90FF"))
        #expect(settings.isUsingCustomAccent)
        #expect(UserDefaults.standard.string(forKey: SettingsManager.Keys.accentColorHex) == "#1E90FF")

        settings.resetAccentColor()
        #expect(!settings.isUsingCustomAccent)
        #expect(UserDefaults.standard.string(forKey: SettingsManager.Keys.accentColorHex) == nil)
    }
}
