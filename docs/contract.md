# Backend contract v1

Frozen before implementation. Any change needs a new version at the bottom.

## Files and ownership

| Path | Owner | Notes |
|---|---|---|
| `tsd.py` | backend | the daemon |
| `tsctl.py` | backend | the only client |
| `install.sh` | backend | venv, config, unit, plugin link |
| `deploy/tunnelshare.service` | backend | systemd user unit template |
| `tests/test_api.sh` | backend | real HTTP checks |
| `templates/`, `static/` | web | friend page only |
| `omarchy-plugin/` | plugin | manifest and QML |

No worker edits another owner's path. No worker commits.

## Config

`~/.config/tunnelshare/config.json`, created by `install.sh`.

```json
{
  "public_port": 8080,
  "admin_port": 8081,
  "data_dir": "~/.local/share/tunnelshare",
  "default_hours": 24,
  "tunnel": {
    "mode": "auto",
    "name": "",
    "public_url": "",
    "transport": "http2"
  }
}
```

`mode`: `auto`, `quick`, or `named`.
`auto` uses `named` when `tunnel.name` is set or `~/.cloudflared/config.yml` exists.
`named` runs `cloudflared tunnel run <name>` and reports `tunnel.public_url`.
`quick` runs `cloudflared tunnel --url http://127.0.0.1:<public_port>`.

Admin token: `~/.config/tunnelshare/admin-token`, mode 0600, created by the
daemon when missing.

## Data

```sql
shares (
  id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  pin_hash TEXT,              -- NULL means no PIN
  pin_salt TEXT,
  pin_fails INTEGER NOT NULL DEFAULT 0,
  locked_until INTEGER NOT NULL DEFAULT 0
);
entries (
  share_id TEXT NOT NULL,
  idx INTEGER NOT NULL,
  rel TEXT NOT NULL,
  path TEXT NOT NULL,
  size INTEGER NOT NULL,
  mime TEXT NOT NULL,
  PRIMARY KEY (share_id, idx)
);
meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
```

`meta` holds `secret_key` (32 random bytes, hex) and `schema` (`1`).

Expiry is derived. No status column. Sweep deletes rows only. The daemon never
deletes, moves, or rewrites a user file.

Share id: `secrets.token_urlsafe(16)`, 128 bits.

PIN: 4 to 8 digits. Stored as PBKDF2-HMAC-SHA256, 210000 iterations, 16 byte
salt, hex. Compare with `hmac.compare_digest`. After 8 wrong tries, lock the
share for 600 seconds (`locked_until`). A correct PIN clears `pin_fails`.

## Public server, 127.0.0.1:`public_port`

Only this port is tunneled.

| Method | Path | Behavior |
|---|---|---|
| GET | `/healthz` | `{"ok":true}` |
| GET | `/s/<id>` | 200 page. 410 if missing, expired, or revoked. PIN form when locked by PIN. |
| POST | `/s/<id>/unlock` | form field `pin`. 303 to `/s/<id>` on success. 200 with an error on failure. 429 while `locked_until` is in the future. |
| GET | `/s/<id>/f/<idx>` | file bytes, `Content-Disposition: attachment`, Range via `send_file(conditional=True)`. 303 to the share page when the PIN cookie is absent or bad. 429 while locked. 410 when expired. 404 for a bad index. |

The unlock state is a Flask session entry: `session["u"] = [share_id, ...]`.
Cookie flags: `HttpOnly=True`, `SameSite=Lax`, `Path=/`. `secret_key` comes
from `meta`, so restarts keep sessions valid.

The page is server rendered HTML. No JavaScript is required to download.
JavaScript is progressive enhancement only.

## Admin server, 127.0.0.1:`admin_port`

Every request needs `X-TS-Token: <admin-token>`. Compare with
`hmac.compare_digest`. Reject requests that carry a non-localhost `Origin`.
Return 401 otherwise. No CORS headers.

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/status` | | `{api:1, version, uptime_s, public_base, tunnel:{mode,state,url,restarts,error,verified}, shares}` |
| POST | `/api/shares` | `{paths:[...], hours, note, pin}` | `{api:1, id, url, path, files, expires_at, pin_set}` |
| GET | `/api/shares` | | `{api:1, shares:[{id, url, path, note, files, size, created_at, expires_at, pin_set, progress}]}` |
| DELETE | `/api/shares/<id>` | | `{api:1, revoked:id}` |
| POST | `/api/tunnel/restart` | | `{api:1, tunnel:{...}}` |

Every share in `/api/shares` carries `progress`, a list of
`{idx, rel, sent, total, percent, active, updated_at}`. `sent` is the highest
byte offset the daemon served for that file. `active` turns false after 60
seconds without an update. The tracker is in memory, resets when the daemon
restarts, and stores no client address or agent.

Validation at the boundary:

- `paths` is a non-empty list of existing files or folders.
- A folder is indexed once, recursively, skipping dot entries. Maximum 5000
  entries, then 400 with a clear message.
- Symlinks resolving outside the shared folder are skipped.
- `hours` is a number, `0 < hours <= 720`, default from config.
- `note` is a string, at most 200 characters.
- `pin` is absent, empty, or 4 to 8 digits. Anything else is 400.
- Unknown fields are ignored.

`public_base` is the quick tunnel URL, or `tunnel.public_url`. Empty when the
tunnel is not up. `url` is `public_base + "/s/" + id` or `""`. `path` is always
`"/s/" + id`, so the panel can still copy something useful when the tunnel is
down.

## Tunnel supervisor

`cloudflared` is a child process of the daemon.

- Quick: `cloudflared tunnel --url http://127.0.0.1:<public_port> --output json`.
  Parse the URL from the JSON lines. If `--output json` is absent or fails,
  fall back to reading stderr for `https://<slug>.trycloudflare.com`.
- Named: `cloudflared tunnel run <name>`.
- On exit, restart after 1, 2, 4, 8, 16, then 30 seconds. Keep the last 200
  log lines in a ring buffer. Expose `state` as `starting`, `up`, `down`, or
  `disabled`.
- On SIGTERM or SIGINT, terminate the child, then stop the servers.
- `state` becomes `up` as soon as `cloudflared` registers the tunnel. The link
  is not hidden while the probe runs. `verified` is true after a local
  `<url>/healthz` request answers 200. Six failed probes before the first
  success, or three after it, set `verified` to false and an advisory `error`.
  The state and URL stay, because a local probe can miss while the edge
  propagates. The probe keeps running and clears the error on recovery.
- `tsctl tunnel restart` kills and restarts the child.
- Missing binary is `state: "down"`, `error: "cloudflared not found"`.

## CLI

`tsctl` reads the config and the admin token. Base URL is
`http://127.0.0.1:<admin_port>`.

```
tsctl status [--json]
tsctl share PATH... [--hours H] [--pin 1234] [--note TEXT] [--json]
tsctl list [--json]
tsctl revoke ID
tsctl tunnel restart
tsctl qr [ID]            # PNG QR of the newest share, or ID, written to stdout path
tsctl install            # runs install.sh
```

Exit codes: 0 ok, 1 usage, 2 daemon unreachable, 3 server error.
Human output stays one line per fact. JSON mode prints one object and nothing
else on stdout.

## Tests

`tests/test_api.sh` runs against real HTTP on ports 18080 and 18081, with a
temporary data dir. It checks at least:

1. create a single-file share, download, bytes identical
2. Range request returns 206 and the right slice
3. folder share indexes nested files with relative paths
4. admin without a token returns 401
5. admin API is absent on the public port
6. PIN share shows the form, wrong PIN fails, right PIN unlocks and downloads
7. 8 wrong PINs lock the share, then 429
8. revoke returns 410
9. expiry returns 410 and leaves the user's file on disk
10. a dotfile is not indexed

`tests/test_tunnel.sh` starts a quick tunnel and fetches a share through the
public URL with curl. It is slow and needs network. Run it once before
declaring the tunnel done.

## Version

Changes to a route, field, or exit code increment the `api` value and add a
note here.
