# Security

## Report a vulnerability

Use GitHub's private vulnerability reporting on this repository:
**Security** -> **Advisories** -> **New draft advisory**. Do not open a public
issue for a vulnerability.

Please include the version or commit, the platform, a minimal reproduction, and
what an attacker gains.

## Scope

- `tsd.py`: the public page, the admin API, PIN handling, the tunnel supervisor,
  and file serving.
- `install.sh`: the installer and the systemd unit it writes.
- `omarchy-plugin/`: the bar widget and panel.
- `site/`: the static landing page.

## Model

- The public port is the only port the tunnel can reach. The admin port is
  bound to loopback and requires a `0600` token.
- Share ids are 128 bits. The link is the capability. A PIN is optional:
  PBKDF2-HMAC-SHA256, 210k rounds, per-share salt, constant-time compare, and a
  ten minute lock after eight wrong tries.
- Folders are indexed once. Symlinks that leave the folder and dot entries are
  skipped. A download request carries an index, never a path.
- Expiry and revoke delete rows only. The daemon never deletes or moves the
  sender's files.
- Download progress is in memory and stores no client identity.
- No telemetry, analytics, or third-party storage. The only peer is Cloudflare.
- The Omarchy plugin runs unsandboxed inside the shell. It calls `tsctl`; it does
  not speak HTTP or SQL. Review the QML before enabling it. The marketplace is
  not a security audit.

## Hardening

- Keep `~/.config/tunnelshare/admin-token` private.
- Use a PIN and a short expiry for sensitive files.
- Prefer a named tunnel with a domain you control for stable links.
- Run the daemon as your normal user, never as root.
