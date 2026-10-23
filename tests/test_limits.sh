#!/usr/bin/env bash
# The per-file cap is a branch in index_paths. Prove it rejects one oversized file.
set -euo pipefail
cd "$(dirname "$0")/.."

PY="${PYTHON:-}"
if [[ -z "$PY" ]]; then
  if [[ -x .venv/bin/python ]]; then PY=.venv/bin/python; else PY=python3; fi
fi

"$PY" - <<'PY'
import os
import tempfile
import tsd

tsd.MAX_FILE_BYTES = 4
fd, path = tempfile.mkstemp()
os.write(fd, b"hello")
os.close(fd)
try:
    tsd.index_paths([path])
except ValueError as exc:
    assert "limit" in str(exc), exc
else:
    raise SystemExit("expected a size limit")
finally:
    os.unlink(path)
print("ok: file size limit")
PY
