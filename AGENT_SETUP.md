# Let an agent install TunnelShare

Copy the block below into Claude, Codex, Cursor, or any agent with shell access.
It installs TunnelShare, starts it, verifies a real download through the public
link, and reports what it did.

The prompt is written to be safe: it asks before sudo, never deletes your files,
and cleans up the test share.

```text
Install TunnelShare from https://github.com/Aakash-chouksey/tunnelshare on this machine.

Rules:
- Do not delete user files. Do not touch files outside the TunnelShare checkout and the paths the installer manages.
- Ask before any command that needs sudo. Show the exact command first.
- If a step fails, stop and report the command and its output. Do not guess.

Steps:
1. Detect the OS and whether Omarchy is present. Check git, python3 (3.10 or newer), python3-venv, pip, cloudflared, and systemctl --user. Report what is missing.
2. Clone the repo to ~/code/tunnelshare if it is not already there.
3. Run ./install.sh --enable.
4. Export PATH="$HOME/.local/bin:$PATH". Wait up to 90 seconds for:
   tsctl status --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("public_base",""))'
   to print a URL. If it stays empty, show systemctl --user status tunnelshare and journalctl --user -u tunnelshare -n 40.
5. Verify a real transfer. Create a 1 MB test file, run:
   tsctl share <file> --hours 1 --note "install test" --json
   curl the returned URL with /f/0, compare the bytes with cmp, then tsctl revoke the id. Leave no test share behind.
6. If Omarchy is present: run omarchy restart shell, then omarchy-shell codejack.tunnelshare open. Confirm the Omatunnel panel opens.
7. Report the public URL, whether the service is enabled, whether cloudflared and the optional tools (qrencode, wl-copy) are present, and the exact next command to share a file.
```

## What the agent needs

The prompt assumes a normal Linux desktop with a user systemd session. On
macOS, tell the agent to follow `docs/manual-setup.md` instead; there is no
systemd user unit.

The installer writes only these paths:

- `~/.local/share/tunnelshare` (app, venv, database)
- `~/.config/tunnelshare` (config, admin token)
- `~/.config/systemd/user/tunnelshare.service`
- `~/.local/bin/tsctl`
- `~/.config/omarchy/plugins/codejack.tunnelshare` (symlink)

Uninstall instructions are in the main README.

## What the agent cannot do

- It cannot choose a good share note for you.
- It cannot install `cloudflared` without your consent if the package manager needs sudo.
- It cannot approve the Omarchy marketplace listing for you.
