# TunnelShare direction

Decided 2026-10-22. Replaces the MVP shape described in `README.md`.

## The problem, from first principles

Five facts cannot be designed away.

1. The bytes live on the sender's machine. That is the point of the tool.
2. The friend has a browser and nothing else.
3. A home network accepts no inbound connection. A tunnel is the only bridge.
4. Something must keep running on the sender's machine while the friend downloads.
5. The friend needs a URL. Any extra step is a choice, not a requirement.

The current code adds a code ceremony, a file copy, a chunked upload, a custom
JavaScript downloader, and a Worker redirect. None of those follow from the five
facts. Each one is a premise that can be tested and removed.

## Four premises that fail

**"The sender uploads through a browser."** False when the sender picks files on
the same machine. The bytes are already on local disk. Sharing becomes a
database insert. The chunked uploader, the `PENDING` state, the `chunks` table,
and the preallocation all serve a byte move that never happens. Deleting them
removes four routes and a state machine.

**"The link needs a second secret."** The current link already carries 48 random
bits. That is the capability. A 6 digit code adds a step for every friend, plus
`code_hash`, `salt`, `attempt_count`, `MAX_ATTEMPTS`, the `LOCKED` state, and
the instruction to send two messages. The code is not needed for the stated
goal.

**"A JavaScript downloader resumes better than the browser."** False. The
browser resumes with HTTP Range, shows progress, retries, and writes straight to
disk. `verify.html` collects every chunk in memory and builds a Blob before
saving. A multi-gigabyte file has no path through that model. The server
already answers Range requests with `206`. The browser uses that.

**"A quick tunnel URL can be made stable with a Worker."** Cloudflare states
that a quick tunnel gets a different hostname on each start and has no uptime
guarantee. The Worker redirects to a moving target. It also needs a KV
namespace, a publish token, and the author's own domain, which is hard coded in
`setup.sh`. A named tunnel gives a stable hostname with no code at all.

## Target design

One daemon and two thin clients.

```
tsd          the daemon. Owns state, files, and the tunnel child process.
  :8080      public. /s/<id> and /d/<id>/<n>. The only tunneled port.
  :8081      admin. /api/shares. Loopback only, never tunneled.
  sqlite     two tables.
  cloudflared child, supervised, quick or named mode.
tsctl        one CLI. The panel, humans, and tests all call this.
omarchy-*    bar widget and panel. No protocol logic in QML.
```

The admin port is a structural boundary. The tunnel points at `8080`, so it
cannot reach `8081`. No `CF-Connecting-IP` check, no owner cookie, no token
file.

Data model.

```sql
shares  (id, created_at, expires_at, note)
entries (share_id, idx, rel, path, size, mime)
```

A share holds entries. Expiry is derived from `expires_at`. There is no status
column and no state machine. Revoking a share deletes rows only. The daemon never
deletes or moves the user's files.

Routes.

| Method | Path | Who |
|---|---|---|
| GET | `/s/<id>` | friend |
| GET | `/d/<id>/<n>` | friend, honors Range |
| POST | `/api/shares` | admin |
| GET | `/api/shares` | admin |
| DELETE | `/api/shares/<id>` | admin |

The friend page is server rendered HTML. Each file is a plain link. No
JavaScript is needed to download. A form field carries an optional PIN when that
feature returns.

Folder shares index the tree once, at share time. The database becomes the only
authority for paths. A request carries an integer index, never a path. Symlinks
that resolve outside the shared root are skipped by construction.

## Evidence

`tsd.py` plus `spike_test.sh` prove the core loop against real HTTP.

```
ok: created single-file share
ok: page lists file and note
ok: download is byte-identical
ok: range request resumes with 206
ok: folder share has 2 entries, rel paths preserved
ok: revoked link returns 410
ok: expiry returns 410 and drops the row
ok: admin API is not on the public port
PASS
```

Size. The old core is 1671 lines across `app.py`, `index.html`, and
`verify.html`. The new daemon and its check are 420 lines.

## What dies

| Path | Reason |
|---|---|
| `workers-site/` | A named tunnel gives a stable hostname. Quick tunnels cannot be stabilized. |
| `.owner-token`, `.publish-token`, `owner_granted()` | The admin port is the boundary. |
| chunked upload, `chunks` table, `PENDING` | The sender owns the bytes. |
| `resolve_status()`, `refresh_status()`, `LOCKED`, `EXHAUSTED` | Derived, or removed with the code. |
| `templates/verify.html` transfer store | The browser downloads and resumes. |
| `check_upload.py` | Replaced by `spike_test.sh`. |
| the file copy into `uploads/` | Serve the original path. |

Keep for now. `setup.sh` shrinks to a dependency check and a systemd unit
install. The browser sender stays as a small convenience with a 100 MB cap,
because the Cloudflare free plan rejects a request body above 100 MB. Large
files go through `tsctl add`.

## Cloudflare limits that shape the product

Sources: [Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/),
[Workers limits](https://developers.cloudflare.com/workers/platform/limits/),
[Routing](https://developers.cloudflare.com/tunnel/concepts/routing/).

- A quick tunnel hostname changes on every start. No uptime guarantee.
- A named tunnel needs a Cloudflare account and a domain on Cloudflare.
- The free plan caps a request body at 100 MB. A response body has no enforced
  limit, so downloads of any size work.
- The free zone terms require a paid service to serve video and other large
  media. Personal sharing with friends is fine. Do not publish this as a public
  file service on a free zone.

## Build order

Each step ends in a check.

1. Port `tsd.py` into the daemon. Add `tsctl`. Keep the old app in place until
   the new one passes. Check: `spike_test.sh` plus one real browser download.
2. Teach the daemon to start, supervise, and stop `cloudflared`. Read the quick
   tunnel URL from its output. Expose status on the admin port. Check: fetch a
   share through the live `trycloudflare.com` URL with `curl`.
3. Ship a systemd user unit. Check: `systemctl --user restart`, then fetch the
   same link again.
4. Polish the friend page. Check: 390 px and 1440 px screenshots, keyboard only
   download, a 5 GB file resumed after a killed download.
5. Build the Omarchy plugin. Bar widget toggles the unit. Panel offers Share
   files and Share folder, lists live links, copies with `wl-copy`. Check: pick
   a folder, copy the link, download it from a phone.
6. Optional, in this order: PIN, browser upload, a receive folder with a quota.

## Product calls

**Receive files.** The phrase can mean the friend sends a file back. That adds a
write path from strangers to the sender's disk, plus a quota, name sanitizing,
and a notification. Default: ship send only first. Add a write only drop folder
in step 6.

**PIN default.** Keep the PIN off by default. One link should work. Offer the
PIN as a per share option for sensitive files. The model keeps one nullable
`pin_hash` column and one check in the download route. That is about 20 lines,
not a state machine.
