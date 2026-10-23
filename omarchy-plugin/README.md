# Omatunnel for Omarchy

Omatunnel is the Omarchy bar panel for TunnelShare. It shares files and folders
through the TunnelShare daemon. Every link expires, and an optional 4 to 8 digit
code gates it.

Omatunnel is a thin client. It never speaks HTTP or SQL: every read and every
action goes through `tsctl`, so the daemon stays the only writer.

## Install

From the TunnelShare checkout:

```sh
./install.sh --enable
```

That links this folder to `~/.config/omarchy/plugins/codejack.tunnelshare` and
enables the plugin. Without `--enable`, link and enable it yourself:

```sh
mkdir -p ~/.config/omarchy/plugins
ln -sfn "$PWD/omarchy-plugin" ~/.config/omarchy/plugins/codejack.tunnelshare
omarchy plugin validate omarchy-plugin
omarchy plugin enable codejack.tunnelshare --yes
```

Reload the shell (`omarchy restart shell`) or the plugin, then the share icon
appears in the right section of the bar. It is also reachable through the panel
IPC target:

```sh
omarchy-shell codejack.tunnelshare open
omarchy-shell codejack.tunnelshare toggle
```

## Install from the plugin store

The repo root carries a manifest for `omarchy plugin add`:

```sh
omarchy plugin add https://github.com/Aakash-chouksey/tunnelshare.git
```

Install the daemon first (`./install.sh --enable`) so `tsctl` and the user unit
exist. The store path adds only the panel. The root manifest points at
`omarchy-plugin/BarWidget.qml`; the manifest in this folder is for the local
symlink. Keep the two in sync.

## Requirements

| Tool | Used for |
|---|---|
| `tsctl` on `PATH` | every read and action |
| `systemctl` (user units) | starting and stopping `tunnelshare.service` |
| `omarchy file select` | picking files and folders |
| `wl-copy` | copying the link and the code |
| `qrencode` | the PNG QR that `tsctl qr` writes |
| `cloudflared` | the tunnel itself, run by the daemon |

Missing `tsctl` shows the command the panel tried. Missing `cloudflared` shows
one line and no toggle that cannot work.

## What the panel calls

| Control | Command |
|---|---|
| state (every 3 s while open, 8 s otherwise) | `tsctl status --json` |
| active links | `tsctl list --json` |
| toggle on | `systemctl --user start tunnelshare` |
| toggle off (one confirm) | `systemctl --user stop tunnelshare` |
| Share files | `omarchy file select --title "Share files" --multiple` |
| Share folder | `omarchy file select --title "Share folder" --directory` |
| share | `tsctl share PATH... --json --hours H [--pin N] [--note TEXT]` |
| restart tunnel | `tsctl tunnel restart` |
| QR | `tsctl qr ID` |
| revoke (two steps in the row) | `tsctl revoke ID` |
| copy link or code | `wl-copy` with the value as its argument |

Paths from the chooser are passed as separate arguments, never through a
shell string, so spaces survive.

`tsctl status` exit code 2 is treated as "daemon down", not as a parse error.

## The panel

1. An `OMATUNNEL` eyebrow, `Sharing` with the toggle, then one status line
   with a signal dot: `LIVE · host`, `TUNNEL · CONNECTING`, `DOWN · ...`, or
   `DAEMON · DOWN` with `Start sharing`.
2. `Share files` as the filled button, `Share folder` beside it. Both show a
   spinner and disable while a share runs.
3. `Require a code` with a 4 to 8 digit field, default `6`. Hours: 1, 24, 72.
   An optional note is collapsed behind `Add a note`.
4. Result card after a share: a `LINK` label with the link, `Copy link`, `QR`,
   and when a code was set, a `CODE` label with the code, `Copy code`, and the
   line `Send the code in a separate message.`
5. Active links with note or file count, expiry (`in 23h`), copy, a two-step
   revoke, and a progress row: the active file, percent, `sent / total`, and a
   thin bar. The count sits at the right of `ACTIVE LINKS`.
6. `NO ACTIVE LINKS` with `Share a file to open one.`
7. Failures land in one plain text line at the bottom, cleared by the next
   action.

The bar icon reads real state: dim when off or the daemon is down, normal while
the tunnel starts, accent when live, urgent on a tunnel error.

## Screenshot

![Omatunnel panel](screenshots/panel.png)

## Limits

The daemon sets 100 GB per file (`TS_MAX_BYTES`), 5000 entries per share, and
720 hours. The root README and [`LIMITS.md`](../LIMITS.md) have the full table.

- A row without a note reads `3 files`. The progress line names the active
  file.
- A path that itself contains a newline cannot survive the line-per-path output
  of `omarchy file select`. Spaces are fine.
