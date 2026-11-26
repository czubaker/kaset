import Foundation
import Testing
@testable import Kaset

// MARK: - AddonInstallerTests

@Suite(.serialized, .tags(.service))
@MainActor
struct AddonInstallerTests {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AddonInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("Each addon picks only its project's Safari build from a release")
    func picksSafariBuilds() {
        #expect(Addon.adBlocker.isBuild(named: "uBOLite_2026.1124.1811.safari.zip"))
        #expect(!Addon.adBlocker.isBuild(named: "uBOLite_2026.1124.1811.chromium.zip"))
        #expect(!Addon.adBlocker.isBuild(named: "uBOLite_2026.1124.1811.firefox.signed.xpi"))
        #expect(Addon.sponsorBlock.isBuild(named: "SafariExtension.zip"))
        #expect(!Addon.sponsorBlock.isBuild(named: "ChromeExtension.zip"))
        #expect(!Addon.sponsorBlock.isBuild(named: "SourceCodeUseThisOne.zip"))
    }

    @Test("A release's digest is used only when it is a well-formed SHA-256")
    func readsReleaseDigests() throws {
        let json = """
        {"tag_name": "1.0", "assets": [
          {"name": "SafariExtension.zip", "browser_download_url": "https://github.com/o/r/releases/download/1.0/SafariExtension.zip",
           "size": 10, "digest": "sha256:\(String(repeating: "AB", count: 32))"},
          {"name": "ChromeExtension.zip", "browser_download_url": "https://github.com/o/r/releases/download/1.0/ChromeExtension.zip",
           "size": 10, "digest": "md5:0123"},
          {"name": "Other.zip", "browser_download_url": "https://github.com/o/r/releases/download/1.0/Other.zip", "size": 10}
        ]}
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.tagName == "1.0")
        #expect(release.assets[0].sha256 == String(repeating: "ab", count: 32))
        #expect(release.assets[1].sha256 == nil)
        #expect(release.assets[2].sha256 == nil)
    }

    @Test("Downloads come only from GitHub over HTTPS")
    func acceptsOnlyGitHubHosts() throws {
        let accepted = [
            "https://github.com/o/r/releases/download/1/a.zip",
            "https://objects.githubusercontent.com/github-production-release-asset/1",
            "https://release-assets.githubusercontent.com/github-production-release-asset/1",
        ]
        let refused = [
            "http://github.com/o/r/releases/download/1/a.zip",
            "https://github.com.example.com/a.zip",
            "https://example.com/githubusercontent.com/a.zip",
        ]
        for string in accepted {
            #expect(try AddonInstaller.isGitHubHost(#require(URL(string: string))), "\(string)")
        }
        for string in refused {
            #expect(try !AddonInstaller.isGitHubHost(#require(URL(string: string))), "\(string)")
        }
    }

    @Test("The digest is the file's SHA-256 in lowercase hex")
    func hashesFiles() throws {
        let directory = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try Data("abc".utf8).write(to: file)
        #expect(try AddonInstaller.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("The extension is the folder with manifest.json, at the root or one folder down")
    func findsTheExtensionFolder() throws {
        let directory = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let flat = directory.appendingPathComponent("flat", isDirectory: true)
        try FileManager.default.createDirectory(at: flat, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: flat.appendingPathComponent("manifest.json"))
        #expect(try AddonInstaller.extensionFolder(in: flat) == flat)

        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        let inner = nested.appendingPathComponent("uBOLite.safari", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: nested.appendingPathComponent("__MACOSX", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: inner.appendingPathComponent("manifest.json"))
        #expect(try AddonInstaller.extensionFolder(in: nested).lastPathComponent == "uBOLite.safari")

        let empty = directory.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: AddonInstaller.InstallError.noManifest) {
            try AddonInstaller.extensionFolder(in: empty)
        }
    }

    @Test("An unpacked archive with a link in it is refused")
    func refusesLinks() throws {
        let directory = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("manifest.json"))
        #expect(AddonInstaller.containsOnlyPlainItems(directory))

        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("escape"),
            withDestinationURL: URL(fileURLWithPath: "/etc")
        )
        #expect(!AddonInstaller.containsOnlyPlainItems(directory))
    }

    @Test("A real zip unpacks with ditto")
    func unpacksZips() async throws {
        let directory = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Addon", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{\"name\": \"Test\"}".utf8).write(to: source.appendingPathComponent("manifest.json"))
        let archive = directory.appendingPathComponent("Addon.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--keepParent", source.path, archive.path]
        try zip.run()
        zip.waitUntilExit()

        let unpacked = try await AddonInstaller.unpack(archive)
        defer { try? FileManager.default.removeItem(at: unpacked) }
        #expect(try AddonInstaller.extensionFolder(in: unpacked).lastPathComponent == "Addon")
    }
}
