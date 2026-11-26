import SwiftUI

// MARK: - StoryboardHoverPreview

/// The frame under the pointer while the progress bar is hovered or scrubbed,
/// with its time, as YouTube shows it. The cell comes from the video's
/// storyboard at its sharpest level; sheets are fetched one at a time as the
/// pointer reaches them and cached by `ImageCache`. Ported from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
struct StoryboardHoverPreview: View {
    let spec: String
    /// 0…1 position under the pointer.
    let fraction: Double
    /// The video's length in seconds, for the time label.
    let duration: Double

    static let previewWidth: CGFloat = 168
    /// The frame, the gap, and the time label: how far above the bar it sits.
    static let totalHeight: CGFloat = 120

    @State private var cellImage: CGImage?

    private var previewSeconds: Int {
        Int(min(max(0, self.fraction), 1) * max(0, self.duration))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.55))
                if let cellImage = self.cellImage {
                    Image(decorative: cellImage, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: Self.previewWidth, height: Self.previewWidth * 9 / 16)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)

            Text(PlayerBarSeekController.formatTime(TimeInterval(self.previewSeconds)))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: .capsule)
        }
        // Storyboard frames are seconds apart, so a second of pointer travel
        // is fine-grained enough; the sheet itself comes from the cache.
        .task(id: self.previewSeconds) {
            if let image = await Self.loadCell(spec: self.spec, fraction: self.fraction) {
                self.cellImage = image
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The sheet holding `fraction` at the spec's sharpest level, with its
    /// cell cut out. Off the main actor; only the `CGImage` comes back.
    nonisolated static func loadCell(spec: String, fraction: Double) async -> CGImage? {
        guard let sheet = StoryboardSheet(spec: spec, level: .max, maxSheets: StoryboardSheet.maxPreviewSheets) else {
            return nil
        }
        let location = sheet.frameLocation(forFraction: fraction)
        guard sheet.sheetURLs.indices.contains(location.sheet),
              let image = await ImageCache.shared.image(for: sheet.sheetURLs[location.sheet]),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let rects = sheet.cellRects(forSheetAt: location.sheet, pixelWidth: cgImage.width, height: cgImage.height)
        guard rects.indices.contains(location.cell) else { return nil }
        return cgImage.cropping(to: rects[location.cell])
    }
}
