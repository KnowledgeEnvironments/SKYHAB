#!/bin/sh
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
data="$HOME/Library/Application Support/skyHAB"
legacy_data="$HOME/Library/Application Support/skyLAB"
logs="$HOME/Library/Logs/skyHAB"
legacy_logs="$HOME/Library/Logs/skyLAB"
agent="$HOME/Library/LaunchAgents/com.skyhab.skyhabd.plist"
legacy_agent="$HOME/Library/LaunchAgents/com.skylab.skylabd.plist"

if [ -d "$legacy_data" ] && [ ! -e "$data" ]; then
  mv "$legacy_data" "$data"
  echo "Migrated runtime data from $legacy_data to $data." >&2
elif [ -e "$legacy_data" ] && [ -e "$data" ]; then
  echo "Both $data and legacy $legacy_data exist; refusing to choose between credential stores." >&2
  exit 1
fi
if [ -d "$legacy_logs" ] && [ ! -e "$logs" ]; then
  mv "$legacy_logs" "$logs"
  echo "Migrated logs from $legacy_logs to $logs." >&2
fi

auth="$data/auth.json"
secrets="$data/device-secrets.json"
inventory="${SKYHAB_INVENTORY_PATH:-${SKYLAB_INVENTORY_PATH:-$data/inventory.json}}"
views="${SKYHAB_VIEWS_PATH:-${SKYLAB_VIEWS_PATH:-$data/views.json}}"
db_dir="${SKYHAB_DB_DIR:-${SKYLAB_DB_DIR:-$data}}"
db="$db_dir/skyhab.sqlite3"
if [ -f "$db_dir/skylab.sqlite3" ] && [ ! -f "$db" ]; then db="$db_dir/skylab.sqlite3"; fi

mkdir -p "$data/bin" "$logs" "$HOME/Library/LaunchAgents" "$db_dir" "$(dirname "$inventory")" "$(dirname "$views")"
chmod 700 "$data"
build_dir="${SKYHAB_BUILD_DIR:-}"
if [ -z "$build_dir" ]; then
  for candidate in "$root/build/release" "$root/build/debug" "$root/build"; do
    if [ -x "$candidate/skyhabd" ] && [ -x "$candidate/skyhabctl" ]; then build_dir=$candidate; break; fi
  done
fi
test -n "$build_dir" && test -x "$build_dir/skyhabd" || { echo "skyhabd is missing; build the project first" >&2; exit 1; }
test -x "$build_dir/skyhabctl" || { echo "skyhabctl is missing; build the project first" >&2; exit 1; }
install -m 0755 "$build_dir/skyhabd" "$data/bin/skyhabd"
install -m 0755 "$build_dir/skyhabctl" "$data/bin/skyhabctl"
ln -sfn skyhabd "$data/bin/skylabd"
ln -sfn skyhabctl "$data/bin/skylabctl"

if [ ! -f "$inventory" ]; then
  install -m 0600 "$root/inventory/inventory.example.json" "$inventory"
  echo "Created example inventory at $inventory; customize it before exposing the service." >&2
fi
if [ ! -f "$views" ]; then
  install -m 0600 "$root/presentation/views.json" "$views"
fi

if [ ! -f "$data/skyhabctl.token" ]; then
  if python3 "$root/tools/manage_tokens.py" "$auth" list 2>/dev/null | awk -F '\t' '$1 == "skyhabctl" && $3 == "active" { found=1 } END { exit !found }'; then
    echo "An active skyhabctl identity exists but its token file is missing; refusing to rotate it implicitly." >&2
    exit 1
  fi
  python3 "$root/tools/manage_tokens.py" "$auth" create skyhabctl --role admin --output "$data/skyhabctl.token"
fi

if [ ! -f "$secrets" ]; then
  printf '%s\n' '{"secrets":{}}' >"$secrets"
  chmod 600 "$secrets"
  echo "Created empty $secrets; add only the credential references required by your adapters." >&2
fi

escape_sed() { printf '%s' "$1" | sed 's/[&|]/\\&/g'; }
sed \
  -e "s|@SKYHABD_PATH@|$(escape_sed "$data/bin/skyhabd")|g" \
  -e "s|@INVENTORY_PATH@|$(escape_sed "$inventory")|g" \
  -e "s|@DATABASE_PATH@|$(escape_sed "$db")|g" \
  -e "s|@BIND_ADDRESS@|${SKYHAB_BIND_ADDRESS:-${SKYLAB_BIND_ADDRESS:-127.0.0.1}}|g" \
  -e "s|@AUTH_PATH@|$(escape_sed "$auth")|g" \
  -e "s|@SECRETS_PATH@|$(escape_sed "$secrets")|g" \
  -e "s|@VIEWS_PATH@|$(escape_sed "$views")|g" \
  -e "s|@LOG_PATH@|$(escape_sed "$logs")|g" \
  "$root/packaging/com.skyhab.skyhabd.plist.in" >"$agent"
plutil -lint "$agent"
launchctl bootout "gui/$(id -u)/com.skyhab.skyhabd" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.skylab.skylabd" 2>/dev/null || true
attempt=0
while ! launchctl bootstrap "gui/$(id -u)" "$agent" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 30 ]; then
    echo "launchd bootstrap failed after $attempt attempts; final diagnostic follows" >&2
    launchctl bootstrap "gui/$(id -u)" "$agent"
    exit 1
  fi
  sleep 1
done
launchctl enable "gui/$(id -u)/com.skyhab.skyhabd"
rm -f "$legacy_agent"
echo "Installed skyhabd and skyhabctl. CLI token file: $data/skyhabctl.token"
echo "Shared client: $root/dist/skyHAB/skyHAB.app"
