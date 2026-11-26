# ADR-0046: Discord Rich Presence from the sandbox

## Status

Accepted

## Context

Users wanted their Discord profile to show what Kaset plays, as KasetPlus
(github.com/Yoddikko/kasetPlus, MIT) does. Discord takes Rich Presence over
a Unix socket, `discord-ipc-0` through `discord-ipc-9`, in the user's real
temporary folder (`/private/var/folders/xx/yyyy/T/`). KasetPlus reaches it by
turning the App Sandbox off. Kaset keeps the sandbox: the app holds signed-in
Google sessions, and the sandbox keeps a compromised page or extension away
from the rest of the user's files.

Measured from the sandboxed debug build: `confstr(_CS_DARWIN_USER_TEMP_DIR)`
returns the container's folder; a read-only or read-write file exception on
`/private/var/folders/` lets the app see the socket but `connect` still fails
with `EPERM`, since the sandbox treats it as a network operation.

## Decision

- `Kaset.entitlements` adds two `com.apple.security.temporary-exception.sbpl`
  rules and nothing broader: reading the listings of `/private/var/folders`
  and its two folder levels (to find the per-user folder the current user
  owns), and `network-outbound` plus metadata reads on
  `/private/var/folders/*/*/T/discord-ipc-[0-9]`. The sandbox stays on.
- The IPC client, activity payload, and service are ported from KasetPlus,
  with the socket folder found by that listing instead of
  `NSTemporaryDirectory()`.
- Kaset uses its own Discord application ("Kaset", ID `1575400153446223943`),
  so profiles read "Listening to Kaset" / "Watching Kaset". The ID is a
  public identifier; the application's public key isn't needed or stored.
- Off by default: Settings → Scrobbling → Discord turns it on and shows the
  connection's state.

## Consequences

- The sandbox exception is specific to Discord's socket names; no other
  file in the user's temporary folders can be read or written.
- The SBPL entitlement suits Kaset's Developer ID and ad-hoc builds; the Mac
  App Store would not accept it.
- Presence updates at most every five seconds and only on change, inside
  Discord's rate limit.
