import AppKit
import SwiftUI

enum PackageResourceLookup {
    private static let resourceBundleName = "Kaset_Kaset.bundle"
    private static let accentColorName = NSColor.Name("AccentColor")

    static let bundle = Self.candidateBundles.first
    static let localizationBundle = Self.bundle

    /// The brand accent as an AppKit color, for views built with AppKit (e.g. NSTableView cells).
    static let brandAccentNSColor: NSColor = {
        if let color = NSColor(named: accentColorName, bundle: Bundle.main) {
            return color
        }

        for bundle in candidateBundles {
            if let color = NSColor(named: accentColorName, bundle: bundle) {
                return color
            }
        }

        return NSColor(srgbRed: 1.0, green: 0.0, blue: 0.337, alpha: 1.0)
    }()

    /// Kaset's brand color, the accent until the user picks another.
    static let defaultBrandAccent = Color(nsColor: Self.brandAccentNSColor)

    /// The accent Kaset's own controls use: the user's pick in Settings →
    /// General, or the brand color. Read it in a view's body so a change
    /// re-tints it.
    @MainActor static var brandAccent: Color {
        SettingsManager.shared.accentColor
    }

    private static let bundleSearchRoots: [Bundle] = {
        var bundles: [Bundle] = [Bundle.main]
        bundles.append(contentsOf: Bundle.allBundles)
        bundles.append(contentsOf: Bundle.allFrameworks)

        var uniqueBundles: [Bundle] = []
        var seenPaths = Set<String>()

        for bundle in bundles {
            guard seenPaths.insert(bundle.bundleURL.path).inserted else { continue }
            uniqueBundles.append(bundle)
        }

        return uniqueBundles
    }()

    private static let candidateBundles: [Bundle] = {
        var bundles: [Bundle] = []
        var seenPaths = Set<String>()

        // 1. Try to find the bundle via current module reference (most reliable)
        // In SwiftPM, targets with resources have a generated Bundle.module.
        // We use a known class from this target to find the right bundle.
        let classBundle = Bundle(for: WebKitManager.self)
        if let moduleBundleURL = classBundle.resourceURL?.appendingPathComponent(Self.resourceBundleName),
           let moduleBundle = Bundle(url: moduleBundleURL)
        {
            bundles.append(moduleBundle)
            seenPaths.insert(moduleBundleURL.path)
        }

        // 2. Standard search roots
        var candidateURLs: [URL] = Self.bundleSearchRoots.flatMap { bundle in
            Self.candidateURLs(for: bundle)
        }
        candidateURLs.append(contentsOf: Self.bundleCandidatesInBuildDirectory())

        for url in candidateURLs {
            guard seenPaths.insert(url.path).inserted else { continue }
            guard let bundle = Bundle(url: url) else { continue }
            bundles.append(bundle)
        }

        return bundles
    }()

    private static func candidateURLs(for bundle: Bundle) -> [URL] {
        [
            bundle.resourceURL?.appendingPathComponent(self.resourceBundleName),
            bundle.bundleURL.appendingPathComponent(self.resourceBundleName),
            bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(self.resourceBundleName),
            bundle.executableURL?.deletingLastPathComponent().appendingPathComponent(self.resourceBundleName),
        ]
        .compactMap(\.self)
    }

    private static func bundleCandidatesInBuildDirectory() -> [URL] {
        let fileManager = FileManager.default
        let buildDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: buildDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var bundleURLs: [URL] = []

        for case let url as URL in enumerator where url.lastPathComponent == Self.resourceBundleName {
            bundleURLs.append(url)
        }

        return bundleURLs
    }
}
