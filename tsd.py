"""TunnelShare daemon (backend contract v1).

Data shape:
    Share = {id, created_at, expires_at, note, pin_hash, pin_salt,
             pin_fails, locked_until}
    Entry = {share_id, idx, rel, path, size, mime}

A Share holds Entries. Expiry is derived from expires_at and is never stored.
Files stay where the user keeps them. The daemon reads them and never copies,
moves, or deletes them.

Two servers, two trust levels:
    public  127.0.0.1:<public_port>  /s/<id>, /s/<id>/unlock, /s/<id>/f/<idx>
    admin   127.0.0.1:<admin_port>   /api/*, needs X-TS-Token
The tunnel points at the public port, so it cannot reach the admin port.
"""
import argparse
import hashlib
import hmac
import http.client
import json
import mimetypes
import os
import re
import secrets
import signal
import sqlite3
import subprocess
import sys
import threading
import time
from collections import deque
from urllib.parse import urlparse

from flask import (
    Flask,
    g,
    jsonify,
    redirect,
    render_template,
    request,
    send_file,
    session,
)
from werkzeug.serving import make_server

APP_VERSION = "0.2.1"
API = 1
MAX_ENTRIES = 5000
MAX_FILE_BYTES = int(os.environ.get("TS_MAX_BYTES", 100_000_000_000))
DEFAULT_HOURS = 24
MAX_HOURS = 720
NOTE_MAX = 200
PIN_MIN, PIN_MAX = 4, 8
PIN_ROUNDS = 210_000
PIN_TRIES = 8
LOCK_SECONDS = 600
BACKOFF = (1, 2, 4, 8, 16, 30)
LOG_LINES = 200
QUICK_URL = re.compile(r"https://[a-z0-9][a-z0-9-]*\.trycloudflare\.com", re.I)
HOME_CONFIG = os.path.expanduser("~/.config/tunnelshare")
if getattr(sys, "frozen", False):
    _exe_dir = os.path.dirname(os.path.abspath(sys.executable))
    if os.path.exists(os.path.join(_exe_dir, "templates")):
        BASE_DIR = _exe_dir
    else:
        BASE_DIR = getattr(sys, "_MEIPASS", _exe_dir)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = {
    "public_port": 8080,
    "admin_port": 8081,
    "data_dir": "~/.local/share/tunnelshare",
    "default_hours": DEFAULT_HOURS,
    "tunnel": {"mode": "auto", "name": "", "public_url": ""},
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS shares (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    pin_hash TEXT,
    pin_salt TEXT,
    pin_fails INTEGER NOT NULL DEFAULT 0,
    locked_until INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS entries (
    share_id TEXT NOT NULL,
    idx INTEGER NOT NULL,
    rel TEXT NOT NULL,
    path TEXT NOT NULL,
    size INTEGER NOT NULL,
    mime TEXT NOT NULL,
    PRIMARY KEY (share_id, idx)
);
CREATE INDEX IF NOT EXISTS entries_share ON entries (share_id, idx);
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


# ------------------------------------------------------------------ config
def config_file(value=None):
    """Accept a directory or a file path. Env TUNNELSHARE_CONFIG overrides."""
    value = os.path.expanduser(value or os.environ.get("TUNNELSHARE_CONFIG") or HOME_CONFIG)
    if value.endswith(".json"):
        return value
    return os.path.join(value, "config.json")


def load_config(path=None):
    path = config_file(path)
    raw = {}
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as fh:
                raw = json.load(fh) or {}
        except (OSError, json.JSONDecodeError) as exc:
            raise SystemExit(f"config error: {path}: {exc}") from None
    cfg = dict(DEFAULT_CONFIG)
    cfg.update({k: v for k, v in raw.items() if k in DEFAULT_CONFIG})
    tunnel = dict(DEFAULT_CONFIG["tunnel"])
    tunnel.update(raw.get("tunnel") or {})
    cfg["tunnel"] = tunnel
    cfg["data_dir"] = os.path.expanduser(str(cfg["data_dir"]))
    return cfg


def ensure_token(path):
    """The admin token. Created 0600 when missing, never world readable."""
    if os.path.exists(path):
        os.chmod(path, 0o600)
        try:
            with open(path, encoding="utf-8") as fh:
                token = fh.read().strip()
        except OSError:
            token = ""
        if token:
            return token
    token = secrets.token_urlsafe(32)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(token + "\n")
    os.chmod(path, 0o600)
    return token


def same_secret(a, b):
    return hmac.compare_digest(str(a).encode("utf-8"), str(b).encode("utf-8"))


# ------------------------------------------------------------------ storage
def connect(path):
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    return db


def init_db(path):
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    except OSError as exc:
        raise SystemExit(f"cannot create data dir: {exc}") from None
    db = connect(path)
    db.executescript(SCHEMA)
    row = db.execute("SELECT value FROM meta WHERE key = 'secret_key'").fetchone()
    if row is not None and row["value"]:
        secret = row["value"]
    else:
        secret = secrets.token_hex(32)
        db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('secret_key', ?)", (secret,))
    db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('schema', '1')")
    db.commit()
    db.close()
    return secret


def sweep(db, now=None):
    """Drop expired shares. Rows only. The user's files are never touched."""
    now = int(now if now is not None else time.time())
    ids = [r["id"] for r in db.execute("SELECT id FROM shares WHERE expires_at <= ?", (now,))]
    for share_id in ids:
        db.execute("DELETE FROM entries WHERE share_id = ?", (share_id,))
        db.execute("DELETE FROM shares WHERE id = ?", (share_id,))
    db.commit()
    return ids


def share_view(db, share_id, now=None):
    """One read model for the page, the download, and the JSON API."""
    now = int(now if now is not None else time.time())
    share = db.execute("SELECT * FROM shares WHERE id = ?", (share_id,)).fetchone()
    if share is None:
        return None
    if now >= share["expires_at"]:
        sweep(db, now)
        return None
    entries = db.execute(
        "SELECT idx, rel, size, mime FROM entries WHERE share_id = ? ORDER BY idx",
        (share_id,),
    ).fetchall()
    return {
        "id": share["id"],
        "created_at": share["created_at"],
        "expires_at": share["expires_at"],
        "note": share["note"],
        "pin_set": bool(share["pin_hash"]),
        "pin_hash": share["pin_hash"],
        "pin_salt": share["pin_salt"],
        "pin_fails": share["pin_fails"],
        "locked_until": share["locked_until"],
        "files": [dict(e) for e in entries],
    }


# ------------------------------------------------------------------ PIN
def hash_pin(pin, salt_hex):
    return hashlib.pbkdf2_hmac(
        "sha256", pin.encode("utf-8"), bytes.fromhex(salt_hex), PIN_ROUNDS
    ).hex()


def pin_format_ok(pin):
    return isinstance(pin, str) and PIN_MIN <= len(pin) <= PIN_MAX and pin.isascii() and pin.isdigit()


def pin_matches(pin, share):
    if not share.get("pin_hash") or not share.get("pin_salt"):
        return False
    return hmac.compare_digest(hash_pin(pin, share["pin_salt"]), share["pin_hash"])


def locked(db, share, now):
    """True while locked. A finished lock clears the fail counter."""
    if share["locked_until"] > now:
        return True
    if share["locked_until"]:
        db.execute("UPDATE shares SET locked_until = 0, pin_fails = 0 WHERE id = ?", (share["id"],))
        db.commit()
        share["locked_until"] = 0
        share["pin_fails"] = 0
    return False


def note_pin_failure(db, share, now):
    fails = share["pin_fails"] + 1
    until = now + LOCK_SECONDS if fails >= PIN_TRIES else 0
    db.execute(
        "UPDATE shares SET pin_fails = ?, locked_until = ? WHERE id = ?",
        (fails, until, share["id"]),
    )
    db.commit()
    share["pin_fails"] = fails
    share["locked_until"] = until
    return until > now


# ------------------------------------------------------------------ indexing
def index_paths(paths):
    """Resolve requested paths into Entry rows. Runs once, at share time."""
    rows = []
    for raw in paths:
        real = os.path.realpath(os.path.expanduser(str(raw)))
        if not os.path.exists(real):
            raise ValueError(f"not found: {raw}")
        if os.path.isdir(real):
            for root, dirs, files in os.walk(real, followlinks=False):
                dirs[:] = sorted(d for d in dirs if not d.startswith("."))
                for name in sorted(files):
                    if name.startswith("."):
                        continue
                    path = os.path.join(root, name)
                    if not os.path.isfile(path):
                        continue
                    resolved = os.path.realpath(path)
                    if resolved != path and not _inside(resolved, real):
                        continue  # symlink pointing out of the shared folder
                    row = _entry_row(resolved, os.path.relpath(path, real))
                    rows.append(_check_size(row))
                    if len(rows) > MAX_ENTRIES:
                        raise ValueError(f"more than {MAX_ENTRIES} entries, share a smaller folder")
        elif os.path.isfile(real):
            row = _entry_row(real, os.path.basename(real))
            rows.append(_check_size(row))
        else:
            raise ValueError(f"not a file or folder: {raw}")
    if not rows:
        raise ValueError("nothing to share")
    return rows


def _inside(path, root):
    try:
        return os.path.commonpath([path, root]) == root
    except ValueError:
        return False


def _entry_row(path, rel):
    return {
        "rel": rel,
        "path": path,
        "size": os.path.getsize(path),
        "mime": mimetypes.guess_type(path)[0] or "application/octet-stream",
    }


def _check_size(row):
    if row["size"] > MAX_FILE_BYTES:
        raise ValueError(
            f"{row['rel']} is {row['size']} bytes, larger than the "
            f"{MAX_FILE_BYTES} byte limit"
        )
    return row


def create_share(db, paths, hours, note="", pin=""):
    rows = index_paths(paths)
    now = int(time.time())
    share_id = secrets.token_urlsafe(16)
    pin_hash = pin_salt = None
    if pin:
        pin_salt = secrets.token_hex(16)
        pin_hash = hash_pin(pin, pin_salt)
    expires_at = now + int(round(float(hours) * 3600))
    db.execute(
        "INSERT INTO shares (id, created_at, expires_at, note, pin_hash, pin_salt)"
        " VALUES (?, ?, ?, ?, ?, ?)",
        (share_id, now, expires_at, note, pin_hash, pin_salt),
    )
    db.executemany(
        "INSERT INTO entries (share_id, idx, rel, path, size, mime) VALUES (?, ?, ?, ?, ?, ?)",
        [(share_id, i, r["rel"], r["path"], r["size"], r["mime"]) for i, r in enumerate(rows)],
    )
    db.commit()
    return share_id, len(rows), expires_at


# ------------------------------------------------------------------ tunnel
class Tunnel:
    """cloudflared as a supervised child process.

    Quick mode: `cloudflared tunnel --url http://127.0.0.1:<port> --output json`.
    The URL is read from JSON lines, with a stderr fallback: stdout and stderr
    are merged into one pipe and every line is scanned for a trycloudflare URL.
    Named mode: `cloudflared tunnel run <name>` and tunnel.public_url from config.
    """

    def __init__(self, cfg, public_port, enabled=True):
        self.cfg_mode = str(cfg.get("mode") or "auto")
        self.name = str(cfg.get("name") or "")
        self.public_url = str(cfg.get("public_url") or "")
        self.port = public_port
        self.enabled = enabled
        self.state = "disabled" if self._disabled() else "starting"
        self.url = ""
        self.restarts = 0
        self.error = ""
        self.lines = deque(maxlen=LOG_LINES)
        self._proc = None
        self._thread = None
        self._stop = threading.Event()
        self._kick = threading.Event()
        self._fail = 0
        self.transport = str(cfg.get("transport") or "http2")
        self.verified = False
        self.ever_up = False
        self._verify_thread = None

    # -- state
    def mode(self):
        if not self.enabled:
            return "disabled"
        mode = self.cfg_mode.lower()
        if mode in ("off", "disabled", "none"):
            return "disabled"
        if mode in ("auto", ""):
            named = bool(self.name) or os.path.exists(os.path.expanduser("~/.cloudflared/config.yml"))
            return "named" if named else "quick"
        return "quick" if mode == "quick" else "named"

    def _disabled(self):
        return not self.enabled or self.cfg_mode.lower() in ("off", "disabled", "none")

    def public_base(self):
        return self.url if self.state == "up" else ""

    def snapshot(self):
        return {
            "mode": self.mode(),
            "state": self.state,
            "url": self.url,
            "restarts": self.restarts,
            "error": self.error,
            "verified": self.verified,
        }

    # -- lifecycle
    def start(self):
        if self._disabled():
            self.state = "disabled"
            return
        if self._thread is not None and self._thread.is_alive():
            return
        self._thread = threading.Thread(target=self._loop, name="tunnel", daemon=True)
        self._thread.start()

    def restart(self):
        if self._disabled():
            return
        self.error = ""
        self._kick.set()
        proc = self._proc
        if proc is not None and proc.poll() is None:
            self.state = "starting"
            self.url = ""
            self.verified = False
            self._terminate(proc)
        if self._thread is None or not self._thread.is_alive():
            self.state = "starting"
            self.start()

    def stop(self):
        self._stop.set()
        self._kick.set()
        proc = self._proc
        if proc is not None:
            self._terminate(proc)
        if self._thread is not None:
            self._thread.join(timeout=8)
        self.state = "down"
        self.url = ""
        self.verified = False

    def _terminate(self, proc):
        try:
            proc.terminate()
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        except OSError:
            pass

    def log(self, line):
        self.lines.append(line)
        print(f"[tunnel] {line}", flush=True)

    def _command(self):
        bin_path = "cloudflared"
        _here = BASE_DIR
        candidates = [
            os.path.join(_here, "cloudflared"),
            os.path.join(_here, "..", "cloudflared"),
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "/usr/bin/cloudflared",
        ]
        for candidate in candidates:
            if os.path.exists(candidate):
                bin_path = candidate
                if not os.access(bin_path, os.X_OK):
                    try:
                        os.chmod(bin_path, 0o755)
                    except OSError:
                        pass
                break
        else:
            found = shutil.which("cloudflared")
            if found:
                bin_path = found
        if self.mode() == "named":
            return [bin_path, "tunnel", "run", self.name]
        return [
            bin_path, "tunnel", "--url", f"http://127.0.0.1:{self.port}", "--output", "json",
        ]

    def _env(self):
        # QUIC stalls through some VPNs. The old shell wrapper forced HTTP/2
        # for the same reason, so keep that default for quick tunnels.
        if self.mode() != "quick":
            return None
        env = os.environ.copy()
        env["TUNNEL_TRANSPORT_PROTOCOL"] = self.transport
        return env

    def _diagnose(self):
        """One human sentence for the last failure, for the panel and status."""
        for line in reversed(self.lines):
            low = line.lower()
            if "name resolution" in low or "no such host" in low:
                return "DNS lookup failed. Check the network or VPN."
            if "429" in low or "rate limit" in low:
                return "Cloudflare rate limited the quick tunnel. Wait a minute."
            if "context deadline exceeded" in low or "timeout" in low:
                return "Cloudflare timed out. Check the network or VPN."
            if "connection refused" in low:
                return "Connection refused. Check the local daemon port."
            if "failed" in low or "error" in low:
                return line[:200]
        return "cloudflared exited"

    def _loop(self):
        while not self._stop.is_set():
            self._kick.clear()
            self.state = "starting"
            self.url = ""
            self.verified = False
            self.ever_up = False
            self.error = ""
            try:
                self._proc = subprocess.Popen(
                    self._command(),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    env=self._env(),
                )
            except FileNotFoundError:
                self._proc = None
                self.state = "down"
                self.error = "cloudflared not found"
                self.log("cloudflared not found on PATH")
                return
            except OSError as exc:
                self._proc = None
                self.state = "down"
                self.error = f"cloudflared failed to start: {exc}"
                self.log(self.error)
                return
            if self.mode() == "named":
                threading.Timer(5.0, self._named_up_if_alive).start()
            self._read_output(self._proc)
            if self._proc is not None:
                self._terminate(self._proc)
            self._proc = None
            if self._stop.is_set():
                break
            self.state = "down"
            self.url = ""
            self.verified = False
            if self._kick.is_set():
                self._fail = 0
                continue
            if not self.error:
                self.error = self._diagnose()
            delay = BACKOFF[min(self._fail, len(BACKOFF) - 1)]
            self._fail += 1
            self.restarts += 1
            if self._kick.wait(delay):
                self._fail = 0

    def _read_output(self, proc):
        for line in proc.stdout:
            line = line.rstrip()
            if not line:
                continue
            self.log(line)
            if self.state == "up" and self.url:
                continue
            match = QUICK_URL.search(line)
            if match:
                self.url = match.group(0)
                # The tunnel is registered. The link is usable now; the local
                # probe only sets `verified`, it never gates the state.
                self.state = "up"
                self.verified = False
                self.error = ""
                self._fail = 0
                self._verify_url(self.url)
            elif self.mode() == "named" and (
                "Registered tunnel connection" in line or "Connection registered" in line
            ):
                self.url = self.public_url
                self.state = "up"
                self.verified = False
                self._fail = 0
                self._verify_url(self.url)

    def _verify_url(self, url):
        if not url:
            return
        thread = self._verify_thread
        if thread is not None and thread.is_alive():
            return
        self._verify_thread = threading.Thread(target=self._verify, args=(url,), daemon=True)
        self._verify_thread.start()

    def _verify(self, url):
        """A URL in the log is not a working link. Prove it from this machine."""
        misses = 0
        while not self._stop.is_set() and self.url == url:
            ok = False
            try:
                parsed = urlparse(url)
                if parsed.scheme in ("http", "https") and parsed.hostname:
                    conn_cls = (
                        http.client.HTTPSConnection
                        if parsed.scheme == "https"
                        else http.client.HTTPConnection
                    )
                    conn = conn_cls(parsed.hostname, parsed.port, timeout=6)
                    try:
                        conn.request("GET", "/healthz")
                        ok = conn.getresponse().status == 200
                    finally:
                        conn.close()
            except Exception:
                ok = False
            if self._stop.is_set() or self.url != url:
                return
            if ok:
                misses = 0
                self.ever_up = True
                self.verified = True
                self.state = "up"
                self.error = ""
            else:
                misses += 1
                if misses >= (3 if self.ever_up else 6):
                    # Advisory only. A local probe can miss while the edge is
                    # still propagating, and the link already works elsewhere.
                    self.verified = False
                    self.error = "local health check failed"
            for _ in range(15):
                if self._stop.is_set() or self.url != url:
                    return
                time.sleep(1)

    def _named_up_if_alive(self):
        proc = self._proc
        if self.state == "starting" and proc is not None and proc.poll() is None:
            self.url = self.public_url
            self.state = "up"
            self.verified = False
            self._verify_url(self.url)


# ------------------------------------------------------------------ pages
def fmt_size(n):
    if n < 1024:
        return f"{n} B"
    if n < 1024 ** 2:
        return f"{n / 1024:.1f} KB"
    if n < 1024 ** 3:
        return f"{n / 1024 ** 2:.1f} MB"
    return f"{n / 1024 ** 3:.2f} GB"


def file_type(rel):
    ext = os.path.splitext(rel)[1].lstrip(".").upper()
    return ext[:5] if ext else "FILE"


def relative_phrase(expires_at, now=None):
    left = int(expires_at) - int(now if now is not None else time.time())
    if left <= 0:
        return "now"
    if left < 3600:
        return f"in {max(1, left // 60)} min"
    if left < 48 * 3600:
        hours = max(1, round(left / 3600))
        return f"in {hours} hour" + ("" if hours == 1 else "s")
    days = max(1, round(left / 86400))
    return f"in {days} day" + ("" if days == 1 else "s")


def share_code(share_id):
    return "".join(ch for ch in share_id if ch.isalnum())[:6].upper()


def share_context(share):
    files = share["files"]
    count = len(files)
    total = sum(item["size"] for item in files)
    note = (share.get("note") or "").strip()
    single = count == 1
    heading = note or (files[0]["rel"] if single else f"{count} files")
    return {
        "share_id": share["id"],
        "code": share_code(share["id"]),
        "note": note,
        "heading": heading,
        "page_title": f"{heading} \u00b7 TunnelShare",
        "count": count,
        "total": fmt_size(total),
        "single": single,
        "files": [
            {
                "idx": item["idx"],
                "rel": item["rel"],
                "type": file_type(item["rel"]),
                "size": fmt_size(item["size"]),
                "href": f"/s/{share['id']}/f/{item['idx']}",
            }
            for item in files
        ],
        "expires_ts": share["expires_at"],
        "expires_in": relative_phrase(share["expires_at"]),
        "expires_stamp": time.strftime("%d %b %H:%M", time.localtime(share["expires_at"])),
    }


def render_share(share):
    return render_template("share.html", **share_context(share))


def render_pin(share, message=""):
    now = int(time.time())
    locked_for = max(0, int(share["locked_until"] - now))
    locked = locked_for > 0
    tries_left = max(0, PIN_TRIES - int(share["pin_fails"]))
    if locked:
        minutes = max(1, (locked_for + 59) // 60)
        message = f"Too many tries. Try again in {minutes} minute" + ("" if minutes == 1 else "s") + "."
    elif message:
        message = f"Wrong code. {tries_left} " + ("try" if tries_left == 1 else "tries") + " left."
    context = share_context(share)
    context.update({"message": message, "locked": locked, "tries_left": tries_left})
    return render_template("gate.html", **context)


def render_notice(title, text):
    return render_template("notice.html", title=title, text=text)


# ------------------------------------------------------------------ progress
class Transfers:
    """In-memory download progress per (share, file).

    Only byte counts. No client address, agent, or identity is stored.
    Progress resets when the daemon restarts.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._rows = {}

    def begin(self, share_id, idx, total, start=0, rel=""):
        now = int(time.time())
        with self._lock:
            row = self._rows.setdefault((share_id, idx), {})
            if start == 0:
                row["sent"] = 0
                row["started"] = now
            else:
                row["sent"] = max(int(start), int(row.get("sent", 0)))
                row.setdefault("started", now)
            row.update({"total": int(total), "active": True, "updated": now,
                        "rel": rel or row.get("rel", "")})

    def update(self, share_id, idx, sent, active=True):
        with self._lock:
            row = self._rows.get((share_id, idx))
            if row is None:
                return
            row["sent"] = max(int(sent), int(row.get("sent", 0)))
            row["active"] = bool(active)
            row["updated"] = int(time.time())

    def finish(self, share_id, idx, sent):
        with self._lock:
            row = self._rows.get((share_id, idx))
            if row is None:
                return
            row["sent"] = max(int(sent), int(row.get("sent", 0)))
            row["active"] = False
            row["updated"] = int(time.time())

    def list(self, share_id):
        now = int(time.time())
        with self._lock:
            out = []
            for key, row in self._rows.items():
                if key[0] != share_id:
                    continue
                total = max(0, int(row.get("total", 0)))
                sent = min(max(0, int(row.get("sent", 0))), total) if total else 0
                out.append({
                    "idx": key[1],
                    "rel": row.get("rel", ""),
                    "sent": sent,
                    "total": total,
                    "percent": int(sent * 100 / total) if total else 0,
                    "active": bool(row.get("active")) and now - int(row.get("updated", 0)) < 60,
                    "updated_at": int(row.get("updated", 0)),
                })
            out.sort(key=lambda item: (not item["active"], -item["sent"]))
            return out

    def drop(self, share_id):
        with self._lock:
            for key in [k for k in self._rows if k[0] == share_id]:
                del self._rows[key]


# ------------------------------------------------------------------ apps
def make_apps(db_path, token, cfg, tunnel, started_at, transfers):
    public = Flask(
        "tsd-public",
        template_folder=os.path.join(BASE_DIR, "templates"),
        static_folder=os.path.join(BASE_DIR, "static"),
        static_url_path="/static",
    )
    admin = Flask("tsd-admin")
    public.secret_key = init_secret_key(db_path)
    public.config.update(
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        SESSION_COOKIE_PATH="/",
    )
    admin.config["TS_TOKEN"] = token

    def db():
        if "db" not in g:
            g.db = connect(db_path)
        return g.db

    def close(_exc=None):
        handle = g.pop("db", None)
        if handle is not None:
            handle.close()

    def harden(resp):
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["Referrer-Policy"] = "no-referrer"
        resp.headers["Cache-Control"] = "no-store"
        return resp

    for app in (public, admin):
        app.teardown_appcontext(close)
        app.after_request(harden)

    @public.after_request
    def csp(resp):
        resp.headers["Content-Security-Policy"] = (
            "default-src 'none'; style-src 'self'; script-src 'self'; "
            "font-src 'self'; img-src 'self' data:; form-action 'self'; "
            "base-uri 'none'; frame-ancestors 'none'"
        )
        return resp

    # -- public: friend
    def unlocked(share_id):
        return share_id in session.get("u", [])

    def mark_unlocked(share_id):
        ids = [i for i in session.get("u", []) if i != share_id]
        ids.append(share_id)
        session["u"] = ids[-20:]

    @public.get("/healthz")
    def health():
        return {"ok": True}

    @public.get("/s/<share_id>")
    def share_page(share_id):
        now = int(time.time())
        share = share_view(db(), share_id, now)
        if share is None:
            return render_notice("This link is not available",
                                 "It expired, or the sender turned sharing off."), 410
        if share["pin_set"]:
            locked(db(), share, now)
            if not unlocked(share_id):
                return render_pin(share)
        return render_share(share)

    @public.post("/s/<share_id>/unlock")
    def unlock(share_id):
        now = int(time.time())
        handle = db()
        share = share_view(handle, share_id, now)
        if share is None:
            return render_notice("This link is not available",
                                 "It expired, or the sender turned sharing off."), 410
        if not share["pin_set"]:
            return redirect(f"/s/{share_id}", code=303)
        if locked(handle, share, now):
            return render_pin(share), 429
        pin = (request.form.get("pin") or "").strip()
        if pin and pin_matches(pin, share):
            handle.execute("UPDATE shares SET pin_fails = 0 WHERE id = ?", (share_id,))
            handle.commit()
            mark_unlocked(share_id)
            return redirect(f"/s/{share_id}", code=303)
        if note_pin_failure(handle, share, now):
            share["locked_until"] = now + LOCK_SECONDS
            return render_pin(share), 429
        return render_pin(share, "Wrong code. Try again."), 200

    @public.get("/s/<share_id>/f/<int:idx>")
    def download(share_id, idx):
        now = int(time.time())
        handle = db()
        share = share_view(handle, share_id, now)
        if share is None:
            return render_notice("This link is not available",
                                 "It expired, or the sender turned sharing off."), 410
        if share["pin_set"]:
            if locked(handle, share, now):
                return render_pin(share), 429
            if not unlocked(share_id):
                return redirect(f"/s/{share_id}", code=303)
        row = handle.execute(
            "SELECT * FROM entries WHERE share_id = ? AND idx = ?", (share_id, idx)
        ).fetchone()
        if row is None or not os.path.isfile(row["path"]):
            return render_notice("File not found", "The sender may have moved or removed it."), 404
        name = os.path.basename(row["path"]) or "download"
        response = send_file(row["path"], mimetype=row["mime"], as_attachment=True,
                             download_name=name, conditional=True)
        if response.status_code in (200, 206) and request.method != "HEAD":
            start = 0
            content_range = response.headers.get("Content-Range", "")
            if content_range:
                try:
                    start = int(content_range.split(" ", 1)[1].split("-", 1)[0])
                except (IndexError, ValueError):
                    start = 0
            transfers.begin(share_id, idx, row["size"], start, row["rel"])
            body = response.response

            def counted():
                sent = start
                try:
                    for chunk in body:
                        data = chunk.encode() if isinstance(chunk, str) else chunk
                        sent += len(data)
                        transfers.update(share_id, idx, sent, True)
                        yield data
                finally:
                    transfers.finish(share_id, idx, sent)

            response.response = counted()
        return response

    # -- admin: every request needs the token and a loopback origin
    @admin.before_request
    def admin_guard():
        origin = request.headers.get("Origin")
        if origin:
            host = urlparse(origin).hostname or ""
            if host not in ("127.0.0.1", "localhost", "::1"):
                return jsonify({"error": "non-localhost origin"}), 401
        sent = request.headers.get("X-TS-Token") or ""
        if not same_secret(sent, admin.config["TS_TOKEN"]):
            return jsonify({"error": "unauthorized"}), 401
        return None

    def share_api(share):
        base = tunnel.public_base()
        return {
            "id": share["id"],
            "url": (base + "/s/" + share["id"]) if base else "",
            "path": "/s/" + share["id"],
            "note": share["note"],
            "files": len(share["files"]),
            "size": sum(f["size"] for f in share["files"]),
            "created_at": share["created_at"],
            "expires_at": share["expires_at"],
            "pin_set": share["pin_set"],
            "progress": transfers.list(share["id"]),
        }

    @admin.get("/api/status")
    def api_status():
        now = int(time.time())
        live = db().execute("SELECT COUNT(*) FROM shares WHERE expires_at > ?", (now,)).fetchone()[0]
        return jsonify({
            "api": API,
            "version": APP_VERSION,
            "uptime_s": now - started_at,
            "public_base": tunnel.public_base(),
            "tunnel": tunnel.snapshot(),
            "shares": live,
        })

    @admin.post("/api/shares")
    def api_create():
        body = request.get_json(force=True, silent=True)
        if not isinstance(body, dict):
            return jsonify({"error": "body must be a JSON object"}), 400
        paths = body.get("paths")
        if not isinstance(paths, list) or not paths:
            return jsonify({"error": "paths must be a non-empty list"}), 400
        hours = body.get("hours", cfg.get("default_hours", DEFAULT_HOURS))
        try:
            hours = float(hours)
        except (TypeError, ValueError):
            return jsonify({"error": "hours must be a number"}), 400
        if not 0 < hours <= MAX_HOURS:
            return jsonify({"error": f"hours must be more than 0 and at most {MAX_HOURS}"}), 400
        note = body.get("note", "")
        if note is None:
            note = ""
        if not isinstance(note, str):
            return jsonify({"error": "note must be a string"}), 400
        if len(note) > NOTE_MAX:
            return jsonify({"error": f"note is longer than {NOTE_MAX} characters"}), 400
        pin = body.get("pin", "")
        if pin is None:
            pin = ""
        if isinstance(pin, int) and not isinstance(pin, bool):
            pin = str(pin)
        if not isinstance(pin, str):
            return jsonify({"error": "pin must be 4 to 8 digits"}), 400
        pin = pin.strip()
        if pin and not pin_format_ok(pin):
            return jsonify({"error": "pin must be 4 to 8 digits"}), 400
        try:
            share_id, files, expires_at = create_share(db(), paths, hours, note, pin)
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400
        return jsonify({
            "api": API,
            "id": share_id,
            "url": (tunnel.public_base() + "/s/" + share_id) if tunnel.public_base() else "",
            "path": "/s/" + share_id,
            "files": files,
            "expires_at": expires_at,
            "pin_set": bool(pin),
        })

    @admin.get("/api/shares")
    def api_list():
        now = int(time.time())
        sweep(db(), now)
        rows = db().execute("SELECT * FROM shares ORDER BY created_at DESC").fetchall()
        out = []
        for row in rows:
            share = share_view(db(), row["id"], now)
            if share is not None:
                out.append(share_api(share))
        return jsonify({"api": API, "shares": out})

    @admin.delete("/api/shares/<share_id>")
    def api_revoke(share_id):
        transfers.drop(share_id)
        db().execute("DELETE FROM entries WHERE share_id = ?", (share_id,))
        db().execute("DELETE FROM shares WHERE id = ?", (share_id,))
        db().commit()
        return jsonify({"api": API, "revoked": share_id})

    @admin.post("/api/tunnel/restart")
    def api_tunnel_restart():
        tunnel.restart()
        return jsonify({"api": API, "tunnel": tunnel.snapshot()})

    return public, admin


def init_secret_key(db_path):
    handle = connect(db_path)
    row = handle.execute("SELECT value FROM meta WHERE key = 'secret_key'").fetchone()
    handle.close()
    return row["value"] if row is not None else secrets.token_hex(32)


# ------------------------------------------------------------------ main
def main():
    parser = argparse.ArgumentParser(description="TunnelShare daemon")
    parser.add_argument("--config", default=None,
                        help="config file or directory (default ~/.config/tunnelshare)")
    parser.add_argument("--data-dir", default=None)
    parser.add_argument("--public-port", type=int, default=None)
    parser.add_argument("--admin-port", type=int, default=None)
    parser.add_argument("--no-tunnel", action="store_true", help="do not start cloudflared")
    args = parser.parse_args()

    try:
        cfg = load_config(args.config)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"config error: {exc}", file=sys.stderr)
        return 1
    if args.data_dir:
        cfg["data_dir"] = os.path.expanduser(args.data_dir)
    if args.public_port:
        cfg["public_port"] = args.public_port
    if args.admin_port:
        cfg["admin_port"] = args.admin_port

    conf_dir = os.path.dirname(config_file(args.config))
    try:
        os.makedirs(conf_dir, exist_ok=True)
        os.makedirs(cfg["data_dir"], exist_ok=True)
    except OSError as exc:
        raise SystemExit(f"cannot create directory: {exc}") from None
    db_path = os.path.join(cfg["data_dir"], "shares.db")
    init_db(db_path)
    token = ensure_token(os.path.join(conf_dir, "admin-token"))
    sweep(connect(db_path))

    started_at = int(time.time())
    tunnel = Tunnel(cfg["tunnel"], cfg["public_port"], enabled=not args.no_tunnel)
    transfers = Transfers()
    public, admin = make_apps(db_path, token, cfg, tunnel, started_at, transfers)

    try:
        public_srv = make_server("127.0.0.1", cfg["public_port"], public, threaded=True)
        admin_srv = make_server("127.0.0.1", cfg["admin_port"], admin, threaded=True)
    except OSError as exc:
        print(f"cannot bind: {exc}", file=sys.stderr)
        return 1

    stop = threading.Event()

    def on_signal(_signum, _frame):
        stop.set()

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    threading.Thread(target=public_srv.serve_forever, name="public", daemon=True).start()
    threading.Thread(target=admin_srv.serve_forever, name="admin", daemon=True).start()
    tunnel.start()

    print(f"public   http://127.0.0.1:{cfg['public_port']}", flush=True)
    print(f"admin    http://127.0.0.1:{cfg['admin_port']}", flush=True)
    print(f"data     {cfg['data_dir']}", flush=True)
    print(f"tunnel   {tunnel.mode()} ({tunnel.state})", flush=True)

    stop.wait()
    tunnel.stop()
    public_srv.shutdown()
    admin_srv.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
