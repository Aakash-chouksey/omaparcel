# TunnelShare

Share a file or a folder from this machine with a friend. The friend opens a
link and downloads. Nothing is uploaded to a third party. Links expire, and an
optional 4 to 8 digit code gates the sensitive ones.

One daemon, two front ends. `tsd` serves the pages and the bytes and supervises
a Cloudflare tunnel. `tsctl` is the only client. The Omarchy panel is a thin
layer over `tsctl`.

## Install

```bash
./install.sh --enable
tsctl status
```

The installer creates a venv, writes `~/.config/tunnelshare/config.json` and a
0600 admin token, installs a systemd user unit, and links the Omarchy plugin
when it finds Omarchy. It needs no sudo. The first run needs network for pip.

Re-run `./install.sh` after you change `tsd.py`, a template, or a static file.

## Share

```bash
tsctl share ~/Pictures/Riverside --hours 24 --note "Riverside, October"
tsctl share ~/contract.pdf --pin 246810 --note "Contract, signed"
tsctl list
tsctl revoke <id>
```

The daemon reads files where they live. It never copies, moves, or deletes them.
A folder is indexed once, so the page lists every file with its relative path.

On Omarchy, open the TunnelShare panel from the bar. The toggle starts and stops
the unit. Share files or a folder, add a note, set an optional code, then copy
the link. The code appears separately, so you can send it in another message.

## Tunnel

`tunnel.mode` is `auto`, `quick`, or `named`.

- `auto` uses a named tunnel when `~/.cloudflared/config.yml` exists or
  `tunnel.name` is set. Otherwise it uses a quick tunnel.
- `quick` needs no account. The hostname changes on every restart, and
  Cloudflare gives it no uptime guarantee.
- `named` needs a Cloudflare account and a domain on Cloudflare. The hostname
  stays the same across restarts.

Quick tunnels use HTTP/2 by default (`tunnel.transport`). QUIC stalls on some
VPNs and Tailscale networks. The daemon probes the public URL against
`/healthz` and reports `verified`. The probe is advisory. A local probe can miss
while Cloudflare propagates a new hostname, and the link still works elsewhere.
The tunnel is up as soon as `cloudflared` registers it. If the probe keeps
failing, `verified` goes false and the status carries
`local health check failed`, but the link stays visible.

## API

Public, tunneled:

- `GET /s/<id>` the friend page
- `POST /s/<id>/unlock` the code form
- `GET /s/<id>/f/<n>` the bytes, honors Range

Admin, loopback only, needs `X-TS-Token`:

- `GET /api/status`
- `POST /api/shares` with `{paths, hours, note, pin}`
- `GET /api/shares`
- `DELETE /api/shares/<id>`
- `POST /api/tunnel/restart`

## Website

`site/` holds the landing page: static HTML, one stylesheet, one small script.
Serve it with `python3 -m http.server -d site` and open http://localhost:8000.
The comparison dock works without a build step and the page degrades to a
static price table without JavaScript.

## Tests

```bash
bash tests/test_api.sh       # real HTTP against a temp data dir
bash tests/test_tunnel.sh    # one real quick tunnel fetch
```

`tests/test_api.sh` covers byte-identical downloads, Range, folder indexing,
admin auth, the public port boundary, the PIN flow, lockout, revoke, expiry, and
dotfile exclusion.

## Security

- Share ids are 128 bits. The link is the capability. A code is optional.
- Codes are stored as PBKDF2-HMAC-SHA256 with 210k rounds and a per-share salt,
  compared in constant time. Eight wrong tries lock the share for ten minutes.
- Admin routes live on a separate loopback port behind a 0600 token. The tunnel
  points only at the public port, so it cannot reach them.
- Folders are indexed once. Symlinks that leave the folder and dot entries are
  skipped. A download request carries an index, never a path.
- Expiry deletes rows only. The sender's files are never touched.

## Limits

- The sender's machine must stay awake and online while a friend downloads.
- A quick tunnel URL changes on restart, so old links stop working. Use a named
  tunnel when a link must survive a restart.
- Cloudflare's free plan caps a request body at 100 MB. Response bodies have no
  enforced limit, so downloads of any size work. Files are served from local
  disk, not uploaded through the edge.
- The free zone terms require a paid service for large media. Personal sharing
  is fine. Do not publish this as a public file service on a free zone.
