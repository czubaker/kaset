import SwiftUI

// MARK: - PlayerBarHeatmapShape

/// YouTube's "most replayed" curve over the width of a progress bar: higher
/// where a slice of the video is replayed more. Closed, it fills down to the
/// bar; open, it is just the line along the top.
struct PlayerBarHeatmapShape: Shape {
    let samples: [YouTubeHeatmapMarker]
    var isClosed = true

    func path(in rect: CGRect) -> Path {
        guard self.samples.count > 1 else { return Path() }
        let points = self.samples.map { sample in
            CGPoint(
                x: rect.minX + rect.width * sample.fraction,
                y: rect.maxY - rect.height * sample.intensity
            )
        }
        let first = points[0]
        let last = points[points.count - 1]

        var path = Path()
        if self.isClosed {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: first.y))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: first.y))
        }
        path.addLine(to: first)
        // Smooth through the midpoints, using each sample as the control point.
        for index in 1 ..< points.count {
            let previous = points[index - 1]
            let current = points[index]
            let middle = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: middle, control: previous)
        }
        path.addLine(to: last)
        path.addLine(to: CGPoint(x: rect.maxX, y: last.y))
        if self.isClosed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - PlayerBarHeatmap

/// The curve as the progress bar shows it while it's hovered or scrubbed:
/// a soft fill in the accent with a line along the top.
struct PlayerBarHeatmap: View {
    let samples: [YouTubeHeatmapMarker]
    let accent: Color

    static let height: CGFloat = 18

    var body: some View {
        ZStack {
            PlayerBarHeatmapShape(samples: self.samples)
                .fill(
                    LinearGradient(
                        colors: [self.accent.opacity(0.32), self.accent.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            PlayerBarHeatmapShape(samples: self.samples, isClosed: false)
                .stroke(self.accent.opacity(0.7), lineWidth: 1)
        }
        .frame(height: Self.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
