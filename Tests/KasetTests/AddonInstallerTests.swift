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

    // MARK: Archive checks

    @Test("Archives with links, absolute paths, or .. steps are refused before unpacking")
    func checksEntriesBeforeUnpacking() {
        let plain = [AddonArchive.Entry(name: "ext/manifest.json", isSymbolicLink: false)]
        #expect(AddonArchive.isSafe(plain))
        #expect(!AddonArchive.isSafe(plain + [AddonArchive.Entry(name: "ext/link", isSymbolicLink: true)]))
        #expect(!AddonArchive.isSafe(plain + [AddonArchive.Entry(name: "../escape.js", isSymbolicLink: false)]))
        #expect(!AddonArchive.isSafe(plain + [AddonArchive.Entry(name: "ext/../../escape.js", isSymbolicLink: false)]))
        #expect(!AddonArchive.isSafe(plain + [AddonArchive.Entry(name: "/etc/escape", isSymbolicLink: false)]))
        #expect(!AddonArchive.isSafe(plain + [AddonArchive.Entry(name: "..\\escape.js", isSymbolicLink: false)]))
        #expect(AddonArchive.isSafe(plain + [AddonArchive.Entry(name: "ext/a..b.js", isSymbolicLink: false)]))
    }

    @Test("A zip's directory lists its entries and marks links")
    func readsZipDirectory() async throws {
        let directory = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Addon", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appendingPathComponent("manifest.json"))
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("escape"),
            withDestinationURL: URL(fileURLWithPath: "/etc")
        )
        let archive = directory.appendingPathComponent("Addon.zip")
        try Self.runTool("/usr/bin/zip", ["-q", "-r", "-y", archive.path, "Addon"], in: directory)

        let entries = try AddonArchive.entries(of: archive)
        #expect(entries.contains(AddonArchive.Entry(name: "Addon/manifest.json", isSymbolicLink: false)))
        #expect(entries.contains(AddonArchive.Entry(name: "Addon/escape", isSymbolicLink: true)))
        await #expect(throws: AddonInstaller.InstallError.badArchive) {
            _ = try await AddonInstaller.unpack(archive)
        }
    }

    // MARK: Install pipeline

    @Test("Install verifies the release's size, digest, and host before adding the addon")
    func installVerifiesDownloads() async throws {
        let directory = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try Self.makeAddonArchive(in: directory)
        let body = try Data(contentsOf: archive)
        let digest = try AddonInstaller.sha256(of: archive)

        struct Case {
            let name: String
            let size: Int
            let digest: String?
            var finalURL: String?
            let expected: AddonInstaller.InstallError
        }
        let cases = [
            Case(name: "wrong digest", size: body.count, digest: String(repeating: "0", count: 64), expected: .verificationFailed),
            Case(name: "wrong size", size: body.count + 1, digest: digest, expected: .verificationFailed),
            Case(name: "no digest", size: body.count, digest: nil, expected: .unverifiable),
            Case(
                name: "off GitHub", size: body.count, digest: digest,
                finalURL: "https://downloads.example.com/SafariExtension.zip", expected: .unverifiable
            ),
        ]
        for testCase in cases {
            let manager = ExtensionsManager(persistenceURL: directory.appendingPathComponent("\(testCase.name).json"))
            let installer = AddonInstaller(manager: manager, session: Self.stubbedSession(
                release: Self.release(size: testCase.size, digest: testCase.digest),
                archive: body,
                archiveResponseURL: testCase.finalURL
            ))
            let leftoversBefore = Self.temporaryAddonItems()
            await #expect(throws: testCase.expected, "\(testCase.name)") {
                _ = try await installer.install(.sponsorBlock)
            }
            #expect(manager.extensions.isEmpty, "\(testCase.name)")
            #expect(Self.temporaryAddonItems() == leftoversBefore, "\(testCase.name)")
        }

        let manager = ExtensionsManager(persistenceURL: directory.appendingPathComponent("ok.json"))
        let installer = AddonInstaller(manager: manager, session: Self.stubbedSession(
            release: Self.release(size: body.count, digest: digest),
            archive: body,
            archiveResponseURL: nil
        ))
        let id = try await installer.install(.sponsorBlock)
        let installed = try #require(installer.installedExtension(for: .sponsorBlock))
        #expect(installed.id == id)
        #expect(installed.version == "1.0")
        #expect(!installed.isEnabled)
    }

    @Test("A release the API doesn't serve installs nothing")
    func installFailsWithoutRelease() async throws {
        let directory = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ExtensionsManager(persistenceURL: directory.appendingPathComponent("extensions.json"))
        AddonStubProtocol.stubs = [Self.releaseURL: AddonStub(status: 404, body: Data())]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AddonStubProtocol.self]
        let installer = AddonInstaller(manager: manager, session: URLSession(configuration: configuration))
        await #expect(throws: URLError.self) {
            _ = try await installer.install(.sponsorBlock)
        }
        #expect(manager.extensions.isEmpty)
    }

    // MARK: Helpers

    private static let releaseURL = "https://api.github.com/repos/ajayyy/SponsorBlock/releases/latest"
    private static let assetURL = "https://github.com/ajayyy/SponsorBlock/releases/download/1.0/SafariExtension.zip"

    private static func release(size: Int, digest: String?) -> Data {
        let digestField = digest.map { ", \"digest\": \"sha256:\($0)\"" } ?? ""
        return Data("""
        {"tag_name": "1.0", "assets": [{"name": "SafariExtension.zip", "browser_download_url": "\(self.assetURL)",
         "size": \(size)\(digestField)}]}
        """.utf8)
    }

    private static func stubbedSession(release: Data, archive: Data, archiveResponseURL: String?) -> URLSession {
        AddonStubProtocol.stubs = [
            self.releaseURL: AddonStub(status: 200, body: release),
            self.assetURL: AddonStub(status: 200, responseURL: archiveResponseURL, body: archive),
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AddonStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func makeAddonArchive(in directory: URL) throws -> URL {
        let source = directory.appendingPathComponent("SponsorBlock", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let manifest = #"{"name": "__MSG_Name__", "manifest_version": 3, "version": "1.0"}"#
        try Data(manifest.utf8).write(to: source.appendingPathComponent("manifest.json"))
        let archive = directory.appendingPathComponent("SafariExtension.zip")
        try self.runTool("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, archive.path], in: directory)
        return archive
    }

    private static func runTool(_ path: String, _ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
    }

    private static func temporaryAddonItems() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("addon-") })
    }
}

// MARK: - AddonStub

struct AddonStub {
    let status: Int
    var responseURL: String?
    let body: Data
}

// MARK: - AddonStubProtocol

/// Serves canned responses by URL; a response URL other than the request's
/// stands for a redirect that ended there.
final class AddonStubProtocol: URLProtocol {
    nonisolated(unsafe) static var stubs: [String: AddonStub] = [:]

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = self.request.url, let stub = Self.stubs[url.absoluteString],
              let responseURL = URL(string: stub.responseURL ?? url.absoluteString),
              let response = HTTPURLResponse(url: responseURL, statusCode: stub.status, httpVersion: nil, headerFields: nil)
        else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: stub.body)
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
