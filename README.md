# SPlayerLyrics

DankMaterialShell DankBar widget plugin for displaying lyrics from SPlayer.

## Features

- Shows the current SPlayer lyric in horizontal and vertical DankBar layouts.
- Uses SPlayer WebSocket data and prefers `yrcData` word lyrics when available.
- Popout panel with now-playing information, album art, playback controls, live lyrics, and connection status.
- Word-level lyric highlighting in the popout when SPlayer provides timed `yrcData.words`.
- Falls back to normal line lyrics from `lrcData` when word timing is unavailable.
- Optional translation display when SPlayer provides translated lyrics.
- Optional hiding while SPlayer is disconnected.

## Requirements

- DankMaterialShell with plugin support.
- SPlayer with WebSocket API enabled.
- Qt 6 WebSockets QML module. Package names vary by distribution:
  - Fedora: `qt6-qtwebsockets-devel`
  - Arch Linux: `qt6-websockets`
  - Debian/Ubuntu: package name may vary by release; install the Qt 6 WebSockets QML module for your distro.
- MPRIS support from the active player is used for album art and seekbar display in the popout.

SPlayer defaults:

- WebSocket: `ws://localhost:25885`
- HTTP API: `http://localhost:25884`

This plugin controls playback through SPlayer's WebSocket `control` command, not the HTTP API.

## Install

Place this plugin directory at:

```sh
~/.config/DankMaterialShell/plugins/SPlayerLyrics
```

Then open DMS Settings -> Plugins, scan plugins, enable `SPlayerLyrics`, and add it to the DankBar widget list.

Reload plugins if needed:

```sh
dms ipc call plugins reload splayerLyrics
```

## Settings

- `Host`: SPlayer WebSocket host. Defaults to `localhost`.
- `Port`: SPlayer WebSocket port. Defaults to `25885`.
- `Prefer Word Lyrics`: Use `yrcData` when available, otherwise fall back to `lrcData`.
- `Show Translation`: Append translated lyrics when SPlayer provides them.
- `Lyric Lookahead`: Advances lyric matching to compensate for display latency.
- `Maximum Bar Width`: Clamps horizontal bar text width.
- `Hide When Disconnected`: Hides the bar pill while SPlayer is unavailable.

## WebSocket Usage

The plugin listens for these SPlayer WebSocket messages:

- `welcome`
- `song-info`
- `song-change`
- `lyric-change`
- `progress-change`
- `status-change`
- `control-response`
- `error`

The plugin sends:

- `get-song-info` after connecting and after playback control responses.
- `control` with `toggle`, `next`, or `prev` from the popout controls.
- `PING` periodically for connection keepalive.

## Notes

- The DankBar pill is intentionally compact; detailed playback information lives in the popout.
- Word-level highlighting is only shown when SPlayer provides usable `yrcData.words` timing.
- The popout seekbar and album art come from the current MPRIS player exposed to DankMaterialShell.
- If SPlayer and the system MPRIS player disagree, the bar lyrics follow SPlayer while album art/seekbar follow MPRIS.
