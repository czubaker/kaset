import CryptoKit
import Foundation

// MARK: - AddonInstaller

/// Installs addons from their projects' official GitHub releases as managed
/// extensions, and removes them with their data. A download is accepted only
/// from GitHub, at the size and SHA-256 digest the release lists for it.
@MainActor
@Observable
final class AddonInstaller {
    static let shared = AddonInstaller()

    enum Phase: Equatable {
        case downloading
        case installing
    }

    enum InstallError: LocalizedError, Equatable {
        case noBuild
        case unverifiable
        case verificationFailed
        case badArchive
        case noManifest

        var errorDescription: String? {
            switch self {
            case .noBuild:
                String(localized: "The project's latest release has no Safari build to install.")
            case .unverifiable:
                String(localized: "The download can't be verified, so it wasn't installed.")
            case .verificationFailed:
                String(localized: "The download doesn't match the release, so it wasn't installed.")
            case .badArchive:
                String(localized: "The download couldn't be unpacked.")
            case .noManifest:
                String(localized: "The download doesn't contain an extension.")
            }
        }
    }

    /// Addons being downloaded or installed right now.
    private(set) var phases: [Addon: Phase] = [:]

    private let manager: ExtensionsManager
    private let session: URLSession
    private let logger = DiagnosticsLogger.extensions

    /// Releases are a few megabytes; anything far larger isn't the build.
    private static let maximumDownloadSize = 64 * 1024 * 1024

    init(manager: ExtensionsManager = .shared, session: URLSession = .shared) {
        self.manager = manager
        self.session = session
    }

    func installedExtension(for addon: Addon) -> ManagedExtension? {
        self.manager.extensions.first { $0.addon == addon }
    }

    /// Downloads and installs the latest release of `addon`, replacing an
    /// older install, and returns the managed extension's ID for its
    /// permission review.
    func install(_ addon: Addon) async throws -> String {
        guard self.phases[addon] == nil else { throw CancellationError() }
        self.phases[addon] = .downloading
        defer { self.phases[addon] = nil }

        let release = try await self.latestRelease(of: addon)
        guard let asset = release.assets.first(where: { addon.isBuild(named: $0.name) }) else {
            throw InstallError.noBuild
        }
        guard let digest = asset.sha256, asset.size > 0, asset.size <= Self.maximumDownloadSize else {
            throw InstallError.unverifiable
        }
        let archive = try await self.download(asset)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard try Self.sha256(of: archive) == digest else {
            throw InstallError.verificationFailed
        }

        self.phases[addon] = .installing
        let unpacked = try await Self.unpack(archive)
        defer { try? FileManager.default.removeItem(at: unpacked) }
        let folder = try Self.extensionFolder(in: unpacked)

        if let existing = self.installedExtension(for: addon) {
            await self.manager.removeExtensionAndData(id: existing.id)
        }
        let id = try self.manager.addExtension(at: folder, addon: addon, version: release.tagName)
        self.logger.info("Installed addon \(addon.rawValue, privacy: .public) \(release.tagName, privacy: .public)")
        return id
    }

    /// Removes `addon`'s files and the data it stored.
    func remove(_ addon: Addon) async {
        guard let installed = self.installedExtension(for: addon) else { return }
        await self.manager.removeExtensionAndData(id: installed.id)
        self.logger.info("Removed addon \(addon.rawValue, privacy: .public)")
    }

    // MARK: Release

    private func latestRelease(of addon: Addon) async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(addon.repository)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await self.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func download(_ asset: GitHubRelease.Asset) async throws -> URL {
        guard Self.isGitHubHost(asset.downloadURL) else { throw InstallError.unverifiable }
        let (temporary, response) = try await self.session.download(from: asset.downloadURL)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("addon-\(UUID().uuidString).zip")
        try FileManager.default.moveItem(at: temporary, to: destination)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, Self.isGitHubHost(finalURL)
        else {
            try? FileManager.default.removeItem(at: destination)
            throw InstallError.unverifiable
        }
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        guard size == asset.size else {
            try? FileManager.default.removeItem(at: destination)
            throw InstallError.verificationFailed
        }
        return destination
    }

    nonisolated static func isGitHubHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Unpacking

    /// Unpacks a zip into a new temporary folder with the system's `ditto`.
    /// The archive's entries are checked first (no links, absolute paths, or
    /// `..` steps), and the unpacked folder again after.
    nonisolated static func unpack(_ archive: URL) async throws -> URL {
        guard let entries = try? AddonArchive.entries(of: archive), AddonArchive.isSafe(entries) else {
            throw InstallError.badArchive
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("addon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let status = try await self.run("/usr/bin/ditto", arguments: ["-x", "-k", archive.path, destination.path])
        guard status == 0, Self.containsOnlyPlainItems(destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw InstallError.badArchive
        }
        return destination
    }

    nonisolated static func containsOnlyPlainItems(_ folder: URL) -> Bool {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return false }
        for case let item as URL in enumerator {
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                return false
            }
            let path = item.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(root + "/") else { return false }
        }
        return true
    }

    /// The folder with the extension's `manifest.json`: the archive's root,
    /// or the one folder it holds.
    nonisolated static func extensionFolder(in unpacked: URL) throws -> URL {
        let fileManager = FileManager.default
        var candidates = [unpacked]
        var depth = 0
        while depth < 3, !candidates.isEmpty {
            if let match = candidates.first(where: {
                fileManager.fileExists(atPath: $0.appendingPathComponent("manifest.json").path)
            }) {
                return match
            }
            candidates = candidates.flatMap { folder in
                ((try? fileManager.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []).filter {
                    $0.lastPathComponent != "__MACOSX"
                        && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                }
            }
            depth += 1
        }
        throw InstallError.noManifest
    }

    nonisolated static func run(_ executable: String, arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - GitHubRelease

/// The parts of GitHub's release API response an install needs.
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let downloadURL: URL
        let size: Int
        /// "sha256:<hex>", which GitHub computes when the asset is uploaded.
        let digest: String?

        var sha256: String? {
            guard let digest, digest.hasPrefix("sha256:") else { return nil }
            let hex = digest.dropFirst("sha256:".count).lowercased()
            return hex.count == 64 && hex.allSatisfy(\.isHexDigit) ? hex : nil
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case size
            case digest
        }
    }

    let tagName: String
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}
