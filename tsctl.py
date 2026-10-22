#!/usr/bin/env python3
"""tsctl - the only TunnelShare client.

Reads ~/.config/tunnelshare/config.json and admin-token, then talks to the
admin port. Every action goes through the daemon, so the daemon stays the only
writer of the database.

Exit codes: 0 ok, 1 usage, 2 daemon unreachable, 3 server error.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HOME_CONFIG = os.path.expanduser("~/.config/tunnelshare")


def config_file():
    value = os.path.expanduser(os.environ.get("TUNNELSHARE_CONFIG") or HOME_CONFIG)
    if value.endswith(".json"):
        return value
    return os.path.join(value, "config.json")


def load_config():
    path = config_file()
    cfg = {"public_port": 8080, "admin_port": 8081,
           "data_dir": os.path.expanduser("~/.local/share/tunnelshare")}
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as fh:
                cfg.update(json.load(fh) or {})
        except (OSError, json.JSONDecodeError) as exc:
            die(1, f"config error: {path}: {exc}")
    cfg["data_dir"] = os.path.expanduser(str(cfg.get("data_dir") or cfg["data_dir"]))
    return cfg


def admin_token():
    override = os.environ.get("TUNNELSHARE_TOKEN")
    if override:
        return override
    path = os.path.join(os.path.dirname(config_file()), "admin-token")
    token = ""
    try:
        with open(path, encoding="utf-8") as fh:
            token = fh.read().strip()
    except OSError:
        die(2, f"admin token not found: {path} (run tsctl install)")
    if not token:
        die(2, f"admin token is empty: {path} (run tsctl install)")
    return token


def die(code, message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(code)


class Parser(argparse.ArgumentParser):
    """Usage errors exit 1, as the contract says."""

    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"{self.prog}: error: {message}", file=sys.stderr)
        raise SystemExit(1)


def call(method, path, body=None):
    cfg = load_config()
    base = f"http://127.0.0.1:{int(cfg.get('admin_port', 8081))}"
    if not base.startswith("http://127.0.0.1:"):
        die(2, f"admin port must be a loopback http port, got {base}")
    token = admin_token()
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("X-TS-Token", token)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as exc:
        try:
            payload = json.loads(exc.read() or b"{}")
        except (ValueError, OSError):
            payload = {}
        die(3, payload.get("error") or f"daemon returned HTTP {exc.code}")
    except (urllib.error.URLError, OSError) as exc:
        die(2, f"daemon unreachable on {base}: {exc}")
    return {}


def fmt_uptime(seconds):
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    return f"{seconds // 3600}h{seconds % 3600 // 60:02d}m"


def fmt_when(epoch):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(int(epoch)))


def emit_json(obj):
    print(json.dumps(obj))


def tunnel_lines(tunnel):
    lines = [f"tunnel   {tunnel.get('state', '?')} ({tunnel.get('mode', '?')})"]
    lines.append(f"url      {tunnel.get('url') or '-'}")
    lines.append(f"restarts {tunnel.get('restarts', 0)}")
    if tunnel.get("verified") is False:
        lines.append("probe    unverified")
    if tunnel.get("error"):
        lines.append(f"error    {tunnel['error']}")
    return lines


def cmd_status(args):
    body = call("GET", "/api/status")
    if args.json:
        return emit_json(body)
    print(f"version  {body.get('version', '?')}")
    print(f"uptime   {fmt_uptime(body.get('uptime_s', 0))}")
    print(f"public   {body.get('public_base') or '-'}")
    for line in tunnel_lines(body.get("tunnel") or {}):
        print(line)
    print(f"shares   {body.get('shares', 0)}")


def cmd_share(args):
    # Resolve on the client, where the path was typed. The daemon runs from
    # its own working directory, so a relative path would resolve there.
    body = {"paths": [os.path.abspath(os.path.expanduser(str(p))) for p in args.paths]}
    if args.hours is not None:
        body["hours"] = args.hours
    if args.pin is not None:
        body["pin"] = args.pin
    if args.note is not None:
        body["note"] = args.note
    out = call("POST", "/api/shares", body)
    if args.json:
        return emit_json(out)
    print(f"link     {out.get('url') or '(tunnel down)'}")
    print(f"path     {out.get('path', '')}")
    print(f"files    {out.get('files', 0)}")
    print(f"expires  {fmt_when(out.get('expires_at', 0))}")
    print(f"pin      {'set' if out.get('pin_set') else 'none'}")


def cmd_list(args):
    body = call("GET", "/api/shares")
    shares = body.get("shares") or []
    if args.json:
        return emit_json(body)
    if not shares:
        print("no shares")
        return
    for share in shares:
        marker = " *pin" if share.get("pin_set") else ""
        note = f"  {share['note']}" if share.get("note") else ""
        print(
            f"{share['id']}  {share['files']} files  {share['size']} B  "
            f"expires {fmt_when(share['expires_at'])}  "
            f"{share.get('url') or '(tunnel down)'}{marker}{note}"
        )


def cmd_revoke(args):
    body = call("DELETE", f"/api/shares/{args.id}")
    print(f"revoked  {body.get('revoked', args.id)}")


def cmd_tunnel_restart(args):
    body = call("POST", "/api/tunnel/restart")
    tunnel = body.get("tunnel") or {}
    if args.json:
        return emit_json(body)
    for line in tunnel_lines(tunnel):
        print(line)


def cmd_qr(args):
    share_id = args.id
    if share_id:
        body = call("GET", "/api/shares")
        match = [s for s in body.get("shares") or [] if s["id"] == share_id]
        if not match:
            die(3, f"no live share with id {share_id}")
        target = match[0]
    else:
        shares = call("GET", "/api/shares").get("shares") or []
        if not shares:
            die(1, "no shares yet, share something first")
        target = shares[0]
    url = target.get("url") or ""
    if not url:
        die(3, "the tunnel is down, there is no public url to encode")
    out = os.path.join(tempfile.gettempdir(), f"tunnelshare-{target['id']}.png")
    try:
        subprocess.run(["qrencode", "-o", out, "-t", "PNG", "-s", "8", "-m", "2", url], check=True)
    except FileNotFoundError:
        die(3, "qrencode not found on PATH")
    except subprocess.CalledProcessError as exc:
        die(3, f"qrencode failed: {exc}")
    print(out)


def cmd_install(args):
    here = os.path.dirname(os.path.abspath(__file__))
    script = os.path.join(here, "install.sh")
    if not os.path.exists(script):
        die(3, f"install.sh not found next to tsctl ({script})")
    raise SystemExit(subprocess.run(["bash", script]).returncode)


def build_parser():
    parser = Parser(prog="tsctl", description="TunnelShare client")
    sub = parser.add_subparsers(dest="command", metavar="COMMAND", parser_class=Parser)

    status = sub.add_parser("status", help="daemon and tunnel state")
    status.add_argument("--json", action="store_true", help="one JSON object on stdout")
    status.set_defaults(func=cmd_status)

    share = sub.add_parser("share", help="share files or folders")
    share.add_argument("paths", nargs="+", metavar="PATH")
    share.add_argument("--hours", type=float, default=None, help="lifetime, 0 < hours <= 720")
    share.add_argument("--pin", default=None, help="4 to 8 digits")
    share.add_argument("--note", default=None, help="short note, at most 200 characters")
    share.add_argument("--json", action="store_true", help="one JSON object on stdout")
    share.set_defaults(func=cmd_share)

    listing = sub.add_parser("list", help="active shares")
    listing.add_argument("--json", action="store_true", help="one JSON object on stdout")
    listing.set_defaults(func=cmd_list)

    revoke = sub.add_parser("revoke", help="kill a share")
    revoke.add_argument("id", metavar="ID")
    revoke.set_defaults(func=cmd_revoke)

    tunnel = sub.add_parser("tunnel", help="tunnel control")
    tunnel_sub = tunnel.add_subparsers(dest="tunnel_command", metavar="ACTION")
    restart = tunnel_sub.add_parser("restart", help="kill and restart cloudflared")
    restart.add_argument("--json", action="store_true", help="one JSON object on stdout")
    restart.set_defaults(func=cmd_tunnel_restart)

    qr = sub.add_parser("qr", help="write a PNG QR of a share and print its path")
    qr.add_argument("id", nargs="?", metavar="ID")
    qr.set_defaults(func=cmd_qr)

    install = sub.add_parser("install", help="run install.sh")
    install.set_defaults(func=cmd_install)

    parser.set_defaults(func=None)
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "func", None) is None:
        parser.print_usage(sys.stderr)
        print("tsctl: error: a command is required", file=sys.stderr)
        return 1
    try:
        args.func(args)
    except BrokenPipeError:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
