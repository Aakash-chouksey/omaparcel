#!/usr/bin/env bash
# Contract v1 HTTP checks. Real servers, real sockets, no mocks.
# Uses ports 18080 (public) and 18081 (admin) and a temporary data dir.
set -euo pipefail
cd "$(dirname "$0")/.."

PY="${PYTHON:-}"
if [[ -z "$PY" ]]; then
  if [[ -x .venv/bin/python ]]; then PY=.venv/bin/python; else PY=python3; fi
fi

PUB=http://127.0.0.1:18080
ADM=http://127.0.0.1:18081
TMP="$(mktemp -d)"
CFG="$TMP/config"
mkdir -p "$CFG"
PID=

cleanup() {
  if [[ -n "$PID" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

jget() {
  "$PY" -c '
import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d = d[int(k)] if k.lstrip("-").isdigit() else d[k]
print(d)
' "$1"
}

cat > "$CFG/config.json" <<JSON
{
  "public_port": 18080,
  "admin_port": 18081,
  "data_dir": "$TMP/data",
  "default_hours": 24,
  "tunnel": {"mode": "off", "name": "", "public_url": ""}
}
JSON

"$PY" tsd.py --config "$CFG" --no-tunnel > "$TMP/tsd.log" 2>&1 &
PID=$!
for _ in $(seq 1 100); do
  curl -sf "$PUB/healthz" >/dev/null 2>&1 && break
  sleep 0.1
done
curl -sf "$PUB/healthz" >/dev/null || { cat "$TMP/tsd.log" >&2; fail "daemon did not start"; }
TOKEN="$(cat "$CFG/admin-token")"
[[ ${#TOKEN} -ge 32 ]] || fail "admin token missing or short"

api() { curl -s -H "X-TS-Token: $TOKEN" -H 'Content-Type: application/json' "$@"; }

# ------------------------------------------------------------------ 1
head -c 1000000 /dev/urandom > "$TMP/blob.bin"
resp=$(api -X POST "$ADM/api/shares" -d "{\"paths\":[\"$TMP/blob.bin\"],\"hours\":1,\"note\":\"check\"}")
id=$(printf '%s' "$resp" | jget id)
[[ -n "$id" ]] || fail "no share id: $resp"
[[ $(printf '%s' "$resp" | jget api) == 1 ]] || fail "missing api:1"
[[ $(printf '%s' "$resp" | jget path) == "/s/$id" ]] || fail "bad path field"
[[ $(printf '%s' "$resp" | jget url) == "" ]] || fail "url must be empty when the tunnel is down"
[[ $(printf '%s' "$resp" | jget pin_set) == "False" ]] || fail "pin_set must be false"
curl -sf "$PUB/s/$id/f/0" -o "$TMP/got.bin"
cmp -s "$TMP/blob.bin" "$TMP/got.bin" || fail "downloaded bytes differ"
curl -s -D "$TMP/head" -o /dev/null "$PUB/s/$id/f/0"
grep -qi '^Content-Disposition: attachment' "$TMP/head" || fail "missing attachment disposition"
ok "single-file share downloads byte-identical bytes"

# ------------------------------------------------------------------ 2
code=$(curl -s -o "$TMP/part" -w '%{http_code}' -H 'Range: bytes=100-199' "$PUB/s/$id/f/0")
[[ $code == 206 ]] || fail "range returned $code, want 206"
[[ $(wc -c < "$TMP/part" | tr -d ' ') == 100 ]] || fail "range body is not 100 bytes"
dd if="$TMP/blob.bin" of="$TMP/expect" bs=1 skip=100 count=100 status=none
cmp -s "$TMP/expect" "$TMP/part" || fail "range slice differs"
ok "range request returns 206 and the right slice"

# ------------------------------------------------------------------ 3
mkdir -p "$TMP/folder/sub/deeper"
echo one > "$TMP/folder/a.txt"
echo two > "$TMP/folder/sub/b.txt"
echo three > "$TMP/folder/sub/deeper/c.txt"
resp=$(api -X POST "$ADM/api/shares" -d "{\"paths\":[\"$TMP/folder\"],\"hours\":1}")
fid=$(printf '%s' "$resp" | jget id)
[[ $(printf '%s' "$resp" | jget files) == 3 ]] || fail "folder share files != 3: $resp"
page=$(curl -sf "$PUB/s/$fid")
grep -q 'sub/b.txt' <<<"$page" || fail "page misses sub/b.txt"
grep -q 'sub/deeper/c.txt' <<<"$page" || fail "page misses sub/deeper/c.txt"
grep -q 'a.txt' <<<"$page" || fail "page misses a.txt"
curl -sf "$PUB/s/$fid/f/1" -o "$TMP/b.txt"
cmp -s "$TMP/folder/sub/b.txt" "$TMP/b.txt" || fail "nested file bytes differ"
ok "folder share indexes nested files with relative paths"

# ------------------------------------------------------------------ 4
code=$(curl -s -o /dev/null -w '%{http_code}' "$ADM/api/status")
[[ $code == 401 ]] || fail "admin without token returned $code, want 401"
code=$(curl -s -o /dev/null -w '%{http_code}' -H "X-TS-Token: wrong" "$ADM/api/status")
[[ $code == 401 ]] || fail "admin with a wrong token returned $code, want 401"
code=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "X-TS-Token: $TOKEN" -H 'Origin: https://evil.example' "$ADM/api/status")
[[ $code == 401 ]] || fail "non-localhost origin returned $code, want 401"
ok "admin without a token or from a foreign origin returns 401"

# ------------------------------------------------------------------ 5
code=$(curl -s -o /dev/null -w '%{http_code}' "$PUB/api/shares")
[[ $code == 404 ]] || fail "public GET /api/shares returned $code, want 404"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{}' "$PUB/api/shares")
[[ $code == 404 ]] || fail "public POST /api/shares returned $code, want 404"
ok "admin API is absent on the public port"

# ------------------------------------------------------------------ 6
resp=$(api -X POST "$ADM/api/shares" \
  -d "{\"paths\":[\"$TMP/blob.bin\"],\"hours\":1,\"note\":\"pin\",\"pin\":\"1234\"}")
pid=$(printf '%s' "$resp" | jget id)
[[ $(printf '%s' "$resp" | jget pin_set) == "True" ]] || fail "pin_set must be true"
page=$(curl -sf "$PUB/s/$pid")
grep -q 'name="pin"' <<<"$page" || fail "PIN share does not show the form"
grep -q 'name="pin"' <<<"$(curl -sf "$PUB/s/$id")" && fail "no-PIN share shows the form"
for _ in $(seq 1 7); do
  code=$(curl -s -o "$TMP/wrong.html" -w '%{http_code}' -d 'pin=0000' "$PUB/s/$pid/unlock")
  [[ $code == 200 ]] || fail "wrong PIN $code, want 200"
done
grep -q 'Wrong code' "$TMP/wrong.html" || fail "wrong PIN gives no error text"
code=$(curl -s -o /dev/null -w '%{http_code}' "$PUB/s/$pid/f/0")
[[ $code == 303 ]] || fail "download without a PIN cookie returned $code, want 303"
code=$(curl -s -c "$TMP/jar" -o /dev/null -w '%{http_code}' -d 'pin=1234' "$PUB/s/$pid/unlock")
[[ $code == 303 ]] || fail "right PIN returned $code, want 303"
code=$(curl -s -o /dev/null -w '%{http_code}' -d 'pin=0000' "$PUB/s/$pid/unlock")
[[ $code == 200 ]] || fail "a right PIN must clear pin_fails (was $code)"
curl -sf -b "$TMP/jar" "$PUB/s/$pid/f/0" -o "$TMP/pin.bin"
cmp -s "$TMP/blob.bin" "$TMP/pin.bin" || fail "PIN download bytes differ"
ok "PIN form, wrong PIN fails, right PIN unlocks and downloads"

# ------------------------------------------------------------------ 7
resp=$(api -X POST "$ADM/api/shares" \
  -d "{\"paths\":[\"$TMP/blob.bin\"],\"hours\":1,\"pin\":\"4321\"}")
lid=$(printf '%s' "$resp" | jget id)
for i in $(seq 1 8); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -d 'pin=0000' "$PUB/s/$lid/unlock")
  if [[ $i -lt 8 ]]; then
    [[ $code == 200 ]] || fail "wrong PIN $i returned $code, want 200 (locked too early)"
  else
    [[ $code == 429 ]] || fail "8th wrong PIN returned $code, want 429"
  fi
done
code=$(curl -s -o /dev/null -w '%{http_code}' -d 'pin=4321' "$PUB/s/$lid/unlock")
[[ $code == 429 ]] || fail "unlock while locked returned $code, want 429"
code=$(curl -s -o /dev/null -w '%{http_code}' "$PUB/s/$lid/f/0")
[[ $code == 429 ]] || fail "download while locked returned $code, want 429"
ok "8 wrong PINs lock the share and every unlock returns 429"

# ------------------------------------------------------------------ 8
resp=$(api -X POST "$ADM/api/shares" -d "{\"paths\":[\"$TMP/blob.bin\"],\"hours\":1}")
rid=$(printf '%s' "$resp" | jget id)
[[ $(api -X DELETE "$ADM/api/shares/$rid" | jget revoked) == "$rid" ]] || fail "revoke response"
code=$(curl -s -o /dev/null -w '%{http_code}' "$PUB/s/$rid")
[[ $code == 410 ]] || fail "revoked page returned $code, want 410"
code=$(curl -s -o /dev/null -w '%{http_code}' "$PUB/s/$rid/f/0")
[[ $code == 410 ]] || fail "revoked download returned $code, want 410"
ok "revoke returns 410"

# ------------------------------------------------------------------ 9
cp "$TMP/blob.bin" "$TMP/keep.bin"
resp=$(api -X POST "$ADM/api/shares" -d "{\"paths\":[\"$TMP/keep.bin\"],\"hours\":1}")
eid=$(printf '%s' "$resp" | jget id)
"$PY" - "$TMP/data/shares.db" "$eid" <<'PY'
import sqlite3, sys, time
db = sqlite3.connect(sys.argv[1])
db.execute("UPDATE shares SET expires_at = ? WHERE id = ?", (int(time.time()) - 1, sys.argv[2]))
db.commit()
PY
code=$(curl -s -o /dev/null -w '%{http_code}' "$PUB/s/$eid")
[[ $code == 410 ]] || fail "expired page returned $code, want 410"
code=$(curl -s -o /dev/null -w '%{http_code}' "$PUB/s/$eid/f/0")
[[ $code == 410 ]] || fail "expired download returned $code, want 410"
[[ -f "$TMP/keep.bin" ]] || fail "expiry removed the user's file"
cmp -s "$TMP/blob.bin" "$TMP/keep.bin" || fail "expiry changed the user's file"
rows=$("$PY" -c 'import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute("SELECT COUNT(*) FROM shares WHERE id=?",(sys.argv[2],)).fetchone()[0])' "$TMP/data/shares.db" "$eid")
[[ $rows == 0 ]] || fail "expired share row survived"
ok "expiry returns 410 and leaves the user's file on disk"

# ------------------------------------------------------------------ 10
mkdir -p "$TMP/dots"
echo visible > "$TMP/dots/visible.txt"
echo hidden > "$TMP/dots/.secret"
resp=$(api -X POST "$ADM/api/shares" -d "{\"paths\":[\"$TMP/dots\"],\"hours\":1}")
did=$(printf '%s' "$resp" | jget id)
[[ $(printf '%s' "$resp" | jget files) == 1 ]] || fail "dotfile was indexed: $resp"
page=$(curl -sf "$PUB/s/$did")
grep -q '.secret' <<<"$page" && fail "dotfile leaked into the page"
grep -q 'visible.txt' <<<"$page" || fail "visible file missing from the page"
ok "a dotfile is not indexed"

echo "PASS"
