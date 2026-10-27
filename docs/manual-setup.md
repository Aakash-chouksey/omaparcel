# Manual setup

The installer is the easy path:

```bash
./install.sh --enable
```

This page is for a machine without systemd, a macOS setup, a named tunnel, or
when you want to run the daemon from source.

## Requirements

| Tool | Needed for |
| --- | --- |
| Python 3.10 or newer | the daemon |
| `cloudflared` | the public link |
| systemd user services | the easy install and the panel toggle |
| `qrencode` | the panel QR |
| `wl-copy` | the panel copy buttons on Wayland |

Install `cloudflared` from
https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/.
On Arch and Omarchy: `sudo pacman -S cloudflared`.

## Run from source, no systemd

```bash
git clone https://github.com/Aakash-chouksey/omatunnel.git
cd omatunnel
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python tsd.py
```

The daemon starts on `127.0.0.1:8080` (public) and `127.0.0.1:8081` (admin).
It uses built-in defaults when `~/.config/tunnelshare/config.json` is missing,
creates the admin token at `~/.config/tunnelshare/admin-token`, and starts
`cloudflared` itself.

In a second terminal:

```bash
python3 tsctl.py status
python3 tsctl.py share ~/Pictures/Riverside --hours 24 --note "Riverside"
```

`tsctl.py` is stdlib only, so the system Python works. It reads
`~/.config/tunnelshare/config.json` and the admin token.

Run the daemon under your own supervisor. `nohup` is enough for a quick test:

```bash
nohup .venv/bin/python tsd.py > /tmp/tunnelshare.log 2>&1 &
```

For a persistent Linux setup, use `install.sh --enable`. For macOS, use a
LaunchAgent.

## macOS

`cloudflared` installs with Homebrew:

```sh
brew install cloudflared
```

Python 3.10 or newer is required. The daemon itself runs the same way as above.
There is no systemd user unit. A small LaunchAgent keeps it alive:

`~/Library/LaunchAgents/com.codejack.tunnelshare.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.codejack.tunnelshare</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/YOU/code/omatunnel/.venv/bin/python</string>
    <string>/Users/YOU/code/omatunnel/tsd.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/tunnelshare.log</string>
  <key>StandardErrorPath</key><string>/tmp/tunnelshare.log</string>
</dict>
</plist>
```

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.codejack.tunnelshare.plist
launchctl kickstart -k gui/$(id -u)/com.codejack.tunnelshare
```

A native menu bar app is available in `macos-app/` ([issue #2](https://github.com/Aakash-chouksey/omatunnel/issues/2)).
Install via the pre-built `Omatunnel.dmg` or build from source with `./macos-app/build_dmg.sh`.

## Named tunnel

A quick tunnel hostname changes on every restart. A named tunnel keeps one
hostname and needs a Cloudflare account and a domain on Cloudflare.

```sh
cloudflared tunnel login
cloudflared tunnel create tunnelshare
cloudflared tunnel route dns tunnelshare share.example.com
```

`~/.cloudflared/config.yml`:

```yaml
tunnel: <tunnel-uuid>
credentials-file: /home/YOU/.cloudflared/<tunnel-uuid>.json
ingress:
  - hostname: share.example.com
    service: http://127.0.0.1:8080
  - service: http_status:404
```

`~/.config/tunnelshare/config.json`:

```json
{
  "tunnel": {
    "mode": "named",
    "name": "tunnelshare",
    "public_url": "https://share.example.com",
    "transport": "http2"
  }
}
```

Restart the service:

```bash
systemctl --user restart tunnelshare
```

With `mode: auto`, the daemon picks named when `tunnel.name` is set or
`~/.cloudflared/config.yml` exists.

## Config

`~/.config/tunnelshare/config.json`:

| Key | Default | Meaning |
| --- | --- | --- |
| `public_port` | `8080` | the tunneled page and file server |
| `admin_port` | `8081` | loopback only, token protected |
| `data_dir` | `~/.local/share/tunnelshare` | database |
| `default_hours` | `24` | default share lifetime |
| `tunnel.mode` | `auto` | `auto`, `quick`, or `named` |
| `tunnel.name` | empty | named tunnel name |
| `tunnel.public_url` | empty | stable URL for named mode |
| `tunnel.transport` | `http2` | `http2` or `quic` |

The admin token lives at `~/.config/tunnelshare/admin-token`, mode `0600`.

## Uninstall

```bash
systemctl --user disable --now tunnelshare
omarchy plugin remove codejack.tunnelshare
rm -f ~/.config/systemd/user/tunnelshare.service ~/.local/bin/tsctl
rm -rf ~/.local/share/tunnelshare ~/.config/tunnelshare
systemctl --user daemon-reload
```

On macOS, use `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.codejack.tunnelshare.plist`
and remove the plist.

Your shared files are outside these paths and are not touched.

## Troubleshooting

`tsctl status` exits 2
: The daemon is not running. Check `systemctl --user status tunnelshare`, or
  start `tsd.py` from source.

`cloudflared not found`
: Install `cloudflared`. Without it the daemon can serve locally but has no
  public URL.

Port 8080 or 8081 is in use
: `ss -ltnp | grep 808`. Stop the other process or change the ports in the
  config. The unit has a start limit, so it stops after repeated failures
  instead of looping.

A quick tunnel returns Cloudflare 530
: The edge could not reach the tunnel. Run `tsctl tunnel restart` and check
  `journalctl --user -u tunnelshare -n 40`. Quick tunnels have no uptime
  guarantee. A named tunnel is more stable.

The friend page says the link is not available
: It expired or the sender revoked it. Create a new share.

The code is locked out
: Eight wrong codes lock the share for ten minutes. Revoke it and share again.

The Omatunnel panel says `tsctl is not on PATH`
: Install the daemon first: `./install.sh --enable`. Omatunnel is only the
  front end.

## Security notes

- The public port is the only port the tunnel can reach. The admin port is
  loopback only and needs the token.
- Omatunnel runs unsandboxed inside the Omarchy shell. Review the QML before
  enabling it. The marketplace is not a security audit.
- Keep `~/.config/tunnelshare/admin-token` private.
- Use a pinned short expiry and a code for sensitive files.
