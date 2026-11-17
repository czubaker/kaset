# ADR-0042: Customizable player bars

## Status

Accepted

## Context

The YouTube Music and YouTube player bars had fixed layouts. Users wanted to
choose which controls show and where, the way Finder's toolbar can be
customized: add blocks such as the channel's avatar with the video title, pick
whether captions, quality, speed, and audio track sit in the video settings
(gear) menu or as buttons of their own, and add spacing.

Each bar has three parts: the media details side, a row of buttons drawn above
the timeline, and the options side. The middle row and the timeline share one
52pt-tall slot. The YouTube bar sizes its sides explicitly: the details side
hides below a width breakpoint so it can't collide with the transport
controls, and tests pinned those widths.

## Decision

Each source has its own `PlayerBarConfiguration`: ordered items for the
leading side, the center row, the trailing side, and (YouTube only) the video
settings menu. `SettingsManager` stores both as JSON. The standard layouts
reproduce the bars as they shipped, so nothing changes until the user
customizes.

- Items are per-source enums (`MusicPlayerBarItem`, `YouTubePlayerBarItem`)
  with a title, a symbol, and the areas they may sit in. Media details blocks
  are two lines tall, so they're limited to the sides. Only the four pickers
  may go in the settings menu.
- Every item appears at most once, except Space and Flexible Space, which can
  repeat. Operations work on positions (area and index) for that reason.
- Decoding keeps known items and drops unknown ones, so layouts survive items
  being added or removed between versions. New items stay off a customized bar
  until the user adds them.
- Both bars render their areas from the configuration through
  `PlayerBarItemRow`. It keeps the bars' gap rule: 6pt between buttons, 8pt
  next to a media details block. Items that draw nothing right now (rating
  buttons when signed out, mix tracks without segments, Float on Top outside
  the detached window) are filtered out first, so they leave no gap.
- The YouTube bar's side widths and its details-hiding breakpoint come from
  `YouTubePlayerBarMetrics`, summed from the items shown, the center row
  included. The standard layout comes out at the previous constants
  (294/141pt details, 210pt options, a 580pt breakpoint), which the tests
  check. Below the breakpoint the leading side drops the video's details and
  rating, which is all the standard layout puts there; other controls placed
  on it stay.
- A side with no items leaves the timeline the same 16pt inset from the
  capsule's end that the YouTube bar already used once its details hid.
- The customization sheet opens from the bar's context menu, View →
  Customize Player Bar…, and the top of the YouTube gear menu, which always
  offers it (so the gear stays on the bar even with no picker in it), and
  edits the bar of the source requested. It
  belongs to the main window, which comes forward (or reopens) to show it,
  also when the detached video window's bar asks. Items drag between the
  areas and the palette, and every change shows on the real bar right away.
  Each item's context menu offers the same moves without dragging, for
  accessibility.

The YouTube bar's menus and media blocks moved into their own views
(`YouTubePlayerBarMenus.swift`, `YouTubePlayerBarTitleBlock.swift`) so the
bar stays within the file and type length limits. The channel block's avatar
comes from the watch page's channel, which the player now keeps alongside the
chapters.

## Consequences

- A new player bar control is an item case with its title, symbol, and areas,
  plus a case in the bar's item view. It's off the bar for anyone who already
  customized it.
- The bars no longer have fixed side widths: a side is as wide as its items.
  Many items on one side shrink the timeline; the sheet doesn't stop that.
- Items can't sit in the timeline's slot itself; the center row stays above
  it, as before.
