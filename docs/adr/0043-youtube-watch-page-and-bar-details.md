# ADR-0043: Customizable YouTube watch page and player bar details

## Status

Accepted

## Context

ADR-0042 made the player bars customizable, but the YouTube bar's media
blocks were fixed: the title over the channel, with or without the channel's
avatar. Users wanted to compose them (an avatar with the title and the view
count, say), to put the channel's Subscribe button and subscriber count on the
bar, and to drop from the watch page whatever they moved to the bar.

The watch page owned the subscription state, and the bar had no channel data
beyond the avatar.

## Decision

- **Detail lines.** The two text blocks, Details (`videoInfo`) and Avatar and
  Details (`channelInfo`), each have two lines the user picks from: video
  title, channel, views, upload date, views and date, subscribers; the second
  line can be empty. `YouTubePlayerBarDetails` stores them per block in
  `SettingsManager`, and decoding falls back to the standard line for an
  unknown field. The standard lines are the title over the channel, so the bar
  looks as it did. The first line keeps the title style (scrolling text); the
  channel opens its page from either line. Lines are picked from the item's
  context menu or a popover on the bar preview.
- **New items.** Channel Avatar alone and Subscribe Button, both limited to
  the bar's sides like the other media blocks.
- **Watch details on the player.** The player keeps what the watch page loaded
  about its video (`YouTubeWatchDetails`: channel, view count, upload date),
  keyed by video ID like the channel was, and falls back to the video card's
  view count and date.
- **Shared subscriptions.** `YouTubeChannelSubscriptions` holds the
  subscription state per channel for the watch page and the bar, so a tap on
  either shows on both. Watch pages seed it; changes are optimistic with
  rollback, and an account change resets it. The bar's button is disabled
  until a watch page has said whether the account is subscribed.
- **Watch page layout.** `YouTubeWatchPageLayout` stores the hidden parts of
  the page (title, views, date, channel, subscribers, Subscribe, chapters,
  comments, related videos) as a set, so a part added later shows by default.
  An option hides whatever the player bar shows, computed from the bar's items
  and detail lines.
- **One sheet.** YouTube's customization sheet has Player Bar and Watch Page
  tabs. View → Customize Watch Page…, the watch page's context menu, and an
  optional toolbar item open it on the Watch Page tab.

## Consequences

- A new detail field is an enum case with its title, a case in the bar's line
  builder, and, if it duplicates a page element, a case in
  `YouTubeWatchPageLayout.playerBarShows`.
- Only the YouTube bar has detail lines; YouTube Music's blocks stay fixed.
- The bar shows views and dates only once the watch page or the video card
  supplied them; until then those lines are empty.
