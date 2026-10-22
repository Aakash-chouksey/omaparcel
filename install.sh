#!/usr/bin/env bash
# TunnelShare installer. No sudo, no root, no network calls except pip.
# Idempotent. Enables the systemd unit and the Omarchy plugin only with --enable.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
ENABLE=0
for arg in "$@"; do
  case "$arg" in
    --enable) ENABLE=1 ;;
    -h|--help)
      echo "usage: install.sh [--enable]" >&2
      echo "  --enable  enable and start the systemd user unit, enable the Omarchy plugin" >&2
      exit 0 ;;
    *)
      echo "usage: install.sh [--enable]" >&2
      exit 1 ;;
  esac
done

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
APP_DIR="$XDG_DATA_HOME/tunnelshare/app"
DATA_DIR="$XDG_DATA_HOME/tunnelshare"
CONF_DIR="$XDG_CONFIG_HOME/tunnelshare"
CONFIG="$CONF_DIR/config.json"
TOKEN="$CONF_DIR/admin-token"
UNIT_DIR="$XDG_CONFIG_HOME/systemd/user"
UNIT="$UNIT_DIR/tunnelshare.service"
BIN_DIR="$HOME/.local/bin"
PLUGIN_LINK="$XDG_CONFIG_HOME/omarchy/plugins/codejack.tunnelshare"

step() { printf '%s\n' "$*"; }
fail() { echo "error: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 not found"
[[ -f "$SRC/tsd.py" && -f "$SRC/tsctl.py" ]] || fail "run install.sh from the TunnelShare source tree"

# 1. directories
mkdir -p "$APP_DIR" "$DATA_DIR" "$CONF_DIR" "$UNIT_DIR" "$BIN_DIR"

# 2. venv and Flask
if [[ ! -x "$APP_DIR/.venv/bin/python" ]]; then
  step "creating venv in $APP_DIR/.venv"
  python3 -m venv "$APP_DIR/.venv" || fail "python3 -m venv failed (install python3-venv)"
fi
step "installing requirements"
"$APP_DIR/.venv/bin/python" -m pip install --quiet --disable-pip-version-check \
  -r "$SRC/requirements.txt" || fail "pip install failed (network needed once)"

# 3. copy the app
install -m 0644 "$SRC/tsd.py" "$APP_DIR/tsd.py"
install -m 0755 "$SRC/tsctl.py" "$APP_DIR/tsctl.py"
install -m 0755 "$SRC/install.sh" "$APP_DIR/install.sh"
install -m 0644 "$SRC/deploy/tunnelshare.service" "$APP_DIR/tunnelshare.service"
install -d "$APP_DIR/templates" "$APP_DIR/static"
cp -a "$SRC/templates/." "$APP_DIR/templates/"
cp -a "$SRC/static/." "$APP_DIR/static/"
if [ -f "$SRC/README.md" ]; then
  install -m 0644 "$SRC/README.md" "$APP_DIR/README.md"
fi
step "installed the app to $APP_DIR"

# 4. config, only when missing
if [[ ! -f "$CONFIG" ]]; then
  cat > "$CONFIG" <<JSON
{
  "public_port": 8080,
  "admin_port": 8081,
  "data_dir": "$DATA_DIR",
  "default_hours": 24,
  "tunnel": {
    "mode": "auto",
    "name": "",
    "public_url": "",
    "transport": "http2"
  }
}
JSON
  step "wrote $CONFIG"
else
  step "kept existing $CONFIG"
fi

# 5. admin token, mode 0600
if [[ ! -s "$TOKEN" ]]; then
  ( umask 077; "$APP_DIR/.venv/bin/python" -c 'import secrets; print(secrets.token_urlsafe(32))' > "$TOKEN" )
  step "created $TOKEN"
fi
chmod 0600 "$TOKEN"

# 6. systemd user unit
sed -e "s|__PYTHON__|$APP_DIR/.venv/bin/python|g" \
    -e "s|__TSD__|$APP_DIR/tsd.py|g" \
    -e "s|__APP_DIR__|$APP_DIR|g" \
    "$SRC/deploy/tunnelshare.service" > "$UNIT"
step "wrote $UNIT"
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload || step "warning: systemctl --user daemon-reload failed"
fi

# 7. tsctl on PATH
ln -sfn "$APP_DIR/tsctl.py" "$BIN_DIR/tsctl"
step "linked $BIN_DIR/tsctl"

# 8. Omarchy plugin symlink
if command -v omarchy >/dev/null 2>&1 || [[ -d "$XDG_CONFIG_HOME/omarchy" ]]; then
  if [[ -d "$SRC/omarchy-plugin" ]]; then
    mkdir -p "$XDG_CONFIG_HOME/omarchy/plugins"
    ln -sfn "$SRC/omarchy-plugin" "$PLUGIN_LINK"
    step "linked $PLUGIN_LINK"
  else
    step "warning: omarchy detected, but $SRC/omarchy-plugin is missing; skipped the plugin"
  fi
else
  step "omarchy not detected, skipped the plugin"
fi

# 9. enable only with a flag
if [[ $ENABLE -eq 1 ]]; then
  command -v systemctl >/dev/null 2>&1 || fail "systemctl not found, cannot --enable"
  systemctl --user enable --now tunnelshare || fail "systemctl --user enable --now tunnelshare failed"
  step "enabled and started tunnelshare"
  if [[ -d "$PLUGIN_LINK" ]] && command -v omarchy >/dev/null 2>&1; then
    omarchy plugin enable codejack.tunnelshare || step "warning: omarchy plugin enable failed"
  fi
else
  if systemctl --user is-enabled tunnelshare >/dev/null 2>&1; then
    step "already enabled. restart with: systemctl --user restart tunnelshare"
  else
    step "not enabled. start with: systemctl --user enable --now tunnelshare"
  fi
fi

step "done. try: tsctl status"
