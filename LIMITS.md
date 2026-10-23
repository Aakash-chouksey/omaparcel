# Omatunnel limits

The numbers come from `tsd.py` and from the Cloudflare limits of a quick tunnel.

| Limit | Value | Where it comes from |
|---|---|---|
| Largest single file | 100 GB (100,000,000,000 bytes) | `MAX_FILE_BYTES`; `TS_MAX_BYTES` overrides |
| Entries per share | 5000 files or folders | `MAX_ENTRIES` |
| Total size per share | Your disk | The daemon sets no total cap |
| Link lifetime | 1 to 720 hours (30 days) | `MAX_HOURS`; default 24 |
| Downloads per link | No cap | Revoke it or let it expire |
| Active shares | No hard cap | SQLite and disk |
| Parallel downloads | 200 in-flight requests on a quick tunnel | Cloudflare quick tunnel; the uplink is the real limit |
| Shares per day | No quota | Your uplink |
| PIN | 4 to 8 digits | 8 tries, then a 10 minute lock |
| Measured speed | 3.1 MB/s | 20 GB takes about 1.8 hours |

## What this means

- The per-file cap is 100 GB. A 20 GB file is fine. A 100 GB file takes about
  9 hours at the measured 3.1 MB/s.
- A share can hold 5000 entries. A folder with more is refused at share time.
- A share can be a folder with 5000 files and any total that fits on your disk.
  The daemon stores no copy; it streams from the original path.
- There is no daily share count. The day is bounded by your uplink: at 3.1 MB/s,
  about 267 GB per day, or 13 files of 20 GB.
- Downloads have no per-link cap. Every live link works until it expires or you
  revoke it.
- Parallel downloads share the one uplink. A quick tunnel accepts 200 in-flight
  requests across all visitors. That is the platform ceiling, not a promise.
  The 200 figure is a quick-tunnel limit; a named tunnel has different limits.
- The PIN locks after 8 wrong tries for 10 minutes.

## Change the file cap

The daemon reads `TS_MAX_BYTES` at start. The default is 100,000,000,000 bytes.

```sh
export TS_MAX_BYTES=200000000000
systemctl --user restart tunnelshare
```

For the user service, add `Environment=TS_MAX_BYTES=200000000000` to the unit.
The cap is per file, not per share.

## Cloudflare side

- The free plan caps a request body at 100 MB. That applies to uploads into
  Cloudflare. This daemon reads the file from your disk and streams it, so the
  cap does not limit a share. The response has no enforced size limit.
- Cloudflare caches responses up to 512 MB, but every share response sends
  `Cache-Control: no-store`, so downloads are not cached.
- Quick tunnels have no uptime guarantee and the URL changes when the tunnel
  restarts. A named tunnel needs a domain.
- Cloudflare's free-zone terms treat very large media as a paid service. A 20 GB
  personal share is a grey area; do not build a public CDN on a free zone.

## Test

`tests/test_limits.sh` sets the cap to 4 bytes and proves a 5 byte file is
rejected.
