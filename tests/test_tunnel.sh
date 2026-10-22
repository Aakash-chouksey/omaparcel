#!/usr/bin/env bash
# One real quick tunnel, then a fetch through the public trycloudflare URL.
# Slow: needs network. Run once before declaring the tunnel done.
set -euo pipefail
cd "$(dirname "$0")/.."

PY="${PYTHON:-}"
if [[ -z "$PY" ]]; then
  if [[ -x .venv/bin/python ]]; then PY=.venv/bin/python; else PY=python3; fi
fi

PUB_PORT=18082
ADM_PORT=18083
TMP="$(mktemp -d)"
CFG="$TMP/config"
mkdir -p "$CFG"
PID=

cleanup() {
  if [[ -n "$PID" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  pkill -f "cloudflared tunnel --url http://127.0.0.1:$PUB_PORT" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

command -v cloudflared >/dev/null 2>&1 || fail "cloudflared not on PATH"

cat > "$CFG/config.json" <<JSON
{
  "public_port": $PUB_PORT,
  "admin_port": $ADM_PORT,
  "data_dir": "$TMP/data",
  "default_hours": 24,
  "tunnel": {"mode": "quick", "name": "", "public_url": ""}
}
JSON

export TUNNELSHARE_CONFIG="$CFG"
"$PY" tsd.py --config "$CFG" > "$TMP/tsd.log" 2>&1 &
PID=$!

curl -sf "http://127.0.0.1:$PUB_PORT/healthz" >/dev/null 2>&1 || sleep 1
curl -sf "http://127.0.0.1:$PUB_PORT/healthz" >/dev/null || { cat "$TMP/tsd.log" >&2; fail "daemon did not start"; }

BASE=""
for _ in $(seq 1 600); do
  BASE=$("$PY" tsctl.py status --json 2>/dev/null | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["public_base"])' 2>/dev/null || true)
  [[ -n "$BASE" ]] && break
  sleep 0.2
done
[[ -n "$BASE" ]] || { tail -20 "$TMP/tsd.log" >&2; fail "quick tunnel did not come up"; }
ok "quick tunnel up at $BASE"

head -c 200000 /dev/urandom > "$TMP/blob.bin"
URL=$("$PY" tsctl.py share "$TMP/blob.bin" --hours 1 --json | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["url"])')
[[ -n "$URL" ]] || fail "share has no public url"
ok "share created at $URL"

for _ in $(seq 1 60); do
  curl -sf --max-time 10 "$BASE/healthz" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf --max-time 30 "$BASE/healthz" >/dev/null || fail "public url is not reachable"

curl -sf --max-time 120 "$URL/f/0" -o "$TMP/got.bin" || fail "download through the tunnel failed"
cmp -s "$TMP/blob.bin" "$TMP/got.bin" || fail "tunnel bytes differ"
ok "fetched the share through the public URL with curl"

pkill -f "cloudflared tunnel --url http://127.0.0.1:$PUB_PORT" 2>/dev/null || true
PID="" # stop the daemon in cleanup
echo "PASS"
