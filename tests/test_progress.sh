#!/usr/bin/env bash
# Download progress is visible while a file streams and reaches 100% after.
set -euo pipefail
cd "$(dirname "$0")/.."

PY="${PYTHON:-}"
if [[ -z "$PY" ]]; then
  if [[ -x .venv/bin/python ]]; then PY=.venv/bin/python; else PY=python3; fi
fi

PUB=http://127.0.0.1:18084
ADM=http://127.0.0.1:18085
TMP="$(mktemp -d)"
CFG="$TMP/config"
mkdir -p "$CFG"
PID=""
CURL_PID=""

cleanup() {
  [[ -n "$CURL_PID" ]] && kill "$CURL_PID" 2>/dev/null || true
  if [[ -n "$PID" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

cat > "$CFG/config.json" <<JSON
{"public_port":18084,"admin_port":18085,"data_dir":"$TMP/data","default_hours":24,
 "tunnel":{"mode":"quick","name":"","public_url":""}}
JSON

"$PY" tsd.py --config "$CFG" --no-tunnel > "$TMP/tsd.log" 2>&1 &
PID=$!
for _ in $(seq 1 50); do curl -sf "$PUB/healthz" >/dev/null && break; sleep 0.2; done
curl -sf "$PUB/healthz" >/dev/null || { cat "$TMP/tsd.log" >&2; fail "daemon did not start"; }

TOKEN=$(cat "$CFG/admin-token")
api() { curl -s -H "X-TS-Token: $TOKEN" -H 'Content-Type: application/json' "$@"; }

head -c 8388608 /dev/urandom > "$TMP/blob.bin"
RESP=$(api -X POST -d "{\"paths\":[\"$TMP/blob.bin\"],\"hours\":1}" "$ADM/api/shares")
ID=$(printf '%s' "$RESP" | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["id"])')
URL="$PUB/s/$ID/f/0"

curl -s --limit-rate 1M -o /dev/null "$URL" &
CURL_PID=$!

SENT=0
for _ in $(seq 1 40); do
  sleep 0.5
  SENT=$(api "$ADM/api/shares" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
p = d["shares"][0].get("progress") or []
print(p[0]["sent"] if p else 0)
')
  [[ $SENT -gt 0 ]] && break
done
[[ $SENT -gt 0 ]] || fail "no progress while the file streams"
ok "progress while streaming: $SENT bytes"

PERCENT=$(api "$ADM/api/shares" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
p = d["shares"][0].get("progress") or []
print(p[0]["percent"] if p else -1)
')
[[ $PERCENT -ge 0 && $PERCENT -lt 100 ]] || fail "mid-download percent was $PERCENT"
ok "mid-download percent: $PERCENT"

wait "$CURL_PID"
CURL_PID=""

FINAL=""
for _ in $(seq 1 20); do
  FINAL=$(api "$ADM/api/shares" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
p = d["shares"][0].get("progress") or []
r = p[0] if p else {}
print(r.get("percent", -1), r.get("sent", 0), r.get("total", 0), r.get("active", None))
')
  [[ "$FINAL" == "100 "*" False" ]] && break
  sleep 0.25
done
set -- $FINAL
[[ "$1" == "100" ]] || fail "final percent was $1 ($FINAL)"
[[ "$2" == "$3" ]] || fail "final sent/total mismatch: $2/$3"
[[ "$4" == "False" ]] || fail "transfer still active after completion: $4"
ok "completed: $2/$3, inactive"

echo PASS
