# Omatunnel panel spec v1

Omatunnel is the sender UI. It never speaks HTTP or SQLite directly. Every
action goes through `tsctl`, so the daemon stays the only writer.

## Plugin files

```
omarchy-plugin/
  manifest.json      id codejack.tunnelshare, name Omatunnel, kinds ["bar-widget"]
  BarWidget.qml      bar icon, state color, opens the panel
  Panel.qml          the whole flow
  ShareRow.qml       one active link row
  README.md          install, screenshots, what it calls
```

`manifest.json` entry point is `BarWidget.qml`. `allowMultiple: false`,
`defaultSection: "right"`, category `Network`, aliases `share`, `files`,
`tunnel`.

`install.sh` symlinks this directory to
`~/.config/omarchy/plugins/codejack.tunnelshare` and calls
`omarchy plugin enable codejack.tunnelshare` only when `--enable` is passed.

## State

Read, never assume. A `Quickshell.Io.Process` runs `tsctl status --json`:

```json
{"api":1,"version":"0.2.0","uptime_s":12,"public_base":"https://x.trycloudflare.com",
 "tunnel":{"mode":"quick","state":"up","url":"https://x.trycloudflare.com",
           "restarts":0,"error":"","verified":true},
 "shares":2}
```

Poll every 3 seconds only while the panel is open. Run once on open. After any
action, run again.

`tsctl status --json` exits 2 when the daemon is down. Treat that as
`daemon_down`, not as a parse error. Show the toggle as off and a "Start
sharing" action.

Do not offer a copyable link while `public_base` is empty. `state: up` means
`cloudflared` registered the tunnel. `verified: true` means the local probe got
a 200. When `verified` is false, keep the link and show `(checking)` until the
error appears, then `(unverified)`. Never hide a registered link.

## Actions

| Control | Command | Notes |
|---|---|---|
| Toggle on | `systemctl --user start tunnelshare` | then poll status |
| Toggle off | `systemctl --user stop tunnelshare` | confirm once, it kills live links |
| Share files | `omarchy file select --title "Share files" --multiple` | then share the returned paths |
| Share folder | `omarchy file select --title "Share folder" --directory` | then share the returned paths |
| Share | `tsctl share <paths...> --json [--hours H] [--pin N] [--note TEXT]` | one call |
| Copy link | `wl-copy` with the URL on stdin | show `Copied` for 1.6s |
| Copy code | `wl-copy` with the PIN on stdin | only for the share just created |
| QR | `tsctl qr <id>` | prints a PNG path, show it in an `Image` |
| Revoke | `tsctl revoke <id>` | two step confirm in the row |
| Restart tunnel | `tsctl tunnel restart` | shown when state is down |

Paths from the file chooser can contain spaces and newlines. Pass them as one
argument each, never through a shell string. `Quickshell.Io.Process` takes an
argument list.

The share call is asynchronous. While it runs, show a spinner in the button and
disable it. A folder with thousands of files can take a second.

## Screen

One panel, width 380, max height 560, vertical scroll for the list.

1. Header. `Sharing` and the toggle. Under it one status line:
   - `Live at x.trycloudflare.com`, link colored
   - `Starting the tunnel`
   - `Tunnel down. Restart`, with the action inline
   - `Daemon down. Start sharing`
2. Primary action. `Share files` as the one filled button. `Share folder` as a
   quiet secondary next to it.
3. Share options, one compact row. `Require a code` toggle. When on, a 4 to 8
   digit field appears, default `6`. Hours as a small select: 1, 24, 72. Note
   is optional and collapsed behind `Add a note`.
4. Result card, only after a share. The link, `Copy link`, `QR`, and when a PIN
   was set the code with `Copy code` and the line `Send the code in a separate
   message.`
5. Active links. Rows with the note or first file name, `+N` for more, the
   expiry as `in 23h`, copy, revoke, and download progress. The progress row
   shows the active file, its percent, `sent / total`, and a thin bar. Refresh
   the share list every 3 seconds while the panel is open.
6. Empty state. `Nothing shared yet. Pick a file to start.`
7. Error line at the bottom, plain text, no modal. Clear it on the next action.

## Visual rules

Follow the shell. Use `Panel`, `PanelSectionHeader`, `PanelActionButton`,
`ToggleSwitch`, `TextField`, `ConfirmDialog`, and the `Color`, `Style`
singletons. Do not hard code colors or fonts. The sample plugin
`~/orca/projects/omarchy-sound-boost` shows the accepted structure, including
the `bar`, `foreground`, `urgent`, and `fontFamily` properties and the
`moduleName` and `ipcTarget` settings.

The bar icon reflects real state:

- daemon down or sharing off: dim icon
- tunnel starting: normal icon
- live: accent icon
- tunnel error: urgent icon

No animation in the bar. The panel may fade in through `Panel` as usual.

## Failure states that must exist

- `cloudflared` missing. Say `cloudflared is not installed` and do not offer a
  toggle that cannot work.
- Tunnel down while the daemon runs. Offer the restart action.
- Daemon down. Offer start.
- `tsctl` missing or not on PATH. Show the command it tried.
- A share fails because a path disappeared. Show the daemon's message verbatim.
- A folder exceeds 5000 files. Show the daemon's message.

## Verification

1. `omarchy plugin validate omarchy-plugin` prints nothing and exits 0.
2. Symlink, enable, restart the shell or reload the plugin. The bar icon appears.
3. Toggle on. `tsctl status --json` reports `tunnel.state` up within 15 seconds.
4. Share a folder with spaces in the name. Copy the link, fetch it with curl from
   the same machine through the public URL.
5. With a PIN on, the friend page asks for the code and accepts it.
6. Toggle off. The link returns 410 or connection refused, and the panel shows
   off.
7. Screenshot the panel in light and dark theme.
