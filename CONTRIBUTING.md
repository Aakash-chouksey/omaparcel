# Contributing

## Development

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python tsd.py --no-tunnel
```

The daemon starts on `127.0.0.1:8080` (public) and `127.0.0.1:8081` (admin). The
admin token is written to `~/.config/tunnelshare/admin-token` on first start.

The web page is server rendered. JavaScript is progressive enhancement only.
The panel is QML over `tsctl`; it never speaks HTTP or SQL.

## Tests

```bash
bash tests/test_api.sh
bash tests/test_progress.sh
bash tests/test_tunnel.sh   # needs cloudflared and network
```

The first two use ports `18080` to `18085` and temporary data dirs. The tunnel
test starts a real quick tunnel and cleans up after itself.

For the plugin:

```bash
omarchy plugin validate omarchy-plugin
```

To check the marketplace layout, copy the repo root without `.venv`, `.git`,
and runtime files, then run `omarchy plugin validate <copy>`.

## Design

Read the contracts before changing behavior:

- `docs/direction.md`
- `docs/contract.md`
- `docs/design-brief.md`
- `docs/panel-spec.md`

The project favors small changes, server rendered HTML, and no new dependency
unless the standard library or an existing dependency cannot do the job.

## Pull requests

- Keep the tests green.
- Keep the plugin manifest versions in sync: `manifest.json` and
  `omarchy-plugin/manifest.json`.
- Do not commit secrets, tokens, databases, uploads, or screenshots with real
  file names.
- Update the README or docs when behavior changes.
- Never commit a change to `site/` that has not been rendered and checked at
  390px and 1280px.
