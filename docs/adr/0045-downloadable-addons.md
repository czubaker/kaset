# ADR-0045: Addons downloaded on demand

## Status

Accepted

## Context

KasetPlus, a fork of Kaset, builds an ad blocker, SponsorBlock, Return
YouTube Dislike, and DeArrow into the app. Users of this fork wanted those
addons without shipping a second app, and without carrying them for
everyone who doesn't use them: an addon should arrive only when it is
turned on, and removing it should leave Kaset as it was before.

A signed, sandboxed app can't download and run native code. It can load web
extensions, which Kaset already supports (`ExtensionsManager`, loaded into
the playback web views through `WKWebExtensionController`).

## Decision

- **Addons are web extensions from their projects' official releases.**
  Settings → Extensions → Addons lists `Addon` cases: uBlock Origin Lite
  (`uBlockOrigin/uBOL-home`) and SponsorBlock (`ajayyy/SponsorBlock`). Nothing
  of them ships with Kaset; their GPL-licensed code is never distributed with
  it.
- **Install** asks GitHub's API for the latest release, takes the project's
  Safari build, and accepts the download only from `github.com` or
  `*.githubusercontent.com` over HTTPS, at the size and the SHA-256 digest
  the release lists. `ditto` unpacks it into a temporary folder; an archive
  with links or entries outside that folder is refused. The folder with
  `manifest.json` goes through `ExtensionsManager.addExtension`, tagged with
  the addon and its release, and then through the same permission review as
  any extension (#589) before it loads at the next launch.
- **Remove** deletes the extension's files and the storage its context kept
  (`WKWebExtensionController.removeData`, matched by the managed ID), and
  asks for a restart if it had loaded. Removing the last extension also
  deletes the empty list and folder.
- Addon entries list under Addons, not under Installed Extensions.
- Return YouTube Dislike and DeArrow are not addons here: they change the
  YouTube page, which Kaset hides behind its native views, so as extensions
  they would do nothing visible.

## Consequences

- The app gains no third-party code or binaries; an addon's code is fetched
  from its project when the user asks for it.
- Updating an addon is installing it again; there is no background update.
- Addons act inside the playback web views: the ad blocker on requests the
  player makes, SponsorBlock on the player's timeline. Native lists and the
  player bar don't show SponsorBlock's segments.
- Kaset has no telemetry of its own. uBlock Origin Lite's default lists
  (uBlock filters, EasyList, EasyPrivacy) also block trackers the YouTube
  player loads.
