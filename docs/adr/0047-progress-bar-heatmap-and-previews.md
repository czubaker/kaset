# ADR-0047: "Most replayed", frame previews, and LIVE on the YouTube progress bar

## Status

Accepted

## Context

Users wanted the progress bar extras KasetPlus (github.com/Yoddikko/kasetPlus,
MIT) has: YouTube's "most replayed" curve, a frame preview while scrubbing,
and a way back to the live head of a rewindable stream.

## Decision

- **Most replayed.** `WatchNextParser.heatmap(of:)` reads the
  `macroMarkersListEntity` of type `MARKER_TYPE_HEATMAP` for the current
  video (verified with api-explorer, November 2026: string `startMillis` and
  `durationMillis`, `intensityScoreNormalized` 0…1; new videos have none
  until YouTube has enough views). The watch page hands the samples to
  `YouTubePlayerService.heatmap`, and `PlayerBarProgressLane` draws them as a
  soft curve above the bar while the bar is hovered or scrubbed, on every
  YouTube bar. Videos opened without a watch page (a link straight to the
  pop-out) have none.
- **Frame preview.** `StoryboardSheet` takes a level and a sheet cap and maps
  a position to its sheet and cell. `StoryboardHoverPreview` shows the cell at
  the spec's sharpest level, with the time, above the bar, held inside its
  ends; sheets are fetched one at a time and cached by `ImageCache`. The
  storyboard spec is now fetched for every video once content plays (one page
  script per video), not only for the `.live` ambient backdrop.
- **LIVE.** For a live stream that can be rewound, the lane shows LIVE in
  place of the remaining time: red within ten seconds of the head, grey
  behind it, and a click seeks to the head.

## Consequences

- One storyboard spec request per video even with the ambient backdrop off.
- The curve and preview appear only on hover or scrub, so the bar looks as
  before at rest.
