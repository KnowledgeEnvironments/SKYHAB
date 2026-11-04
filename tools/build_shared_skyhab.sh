#!/bin/sh
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
auth_data="$HOME/Library/Application Support/skyHAB"
output="$root/dist/skyHAB"
stage="$root/build/skyHAB.shared.app"
iconset="$root/build/skyHAB.iconset"
client_host="${SKYHAB_CLIENT_HOST:-${SKYLAB_CLIENT_HOST:-127.0.0.1}}"
client_port="${SKYHAB_CLIENT_PORT:-${SKYLAB_CLIENT_PORT:-3636}}"
client_name="${SKYHAB_CLIENT_NAME:-${SKYLAB_CLIENT_NAME:-skyHAB.shared}}"

case "$client_host" in *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-]*) echo "Invalid SKYHAB_CLIENT_HOST" >&2; exit 2;; esac
case "$client_port" in ''|*[!0-9]*) echo "Invalid SKYHAB_CLIENT_PORT" >&2; exit 2;; esac
case "$client_name" in *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*) echo "Invalid SKYHAB_CLIENT_NAME" >&2; exit 2;; esac

mkdir -p "$root/build" "$output" "$auth_data"

rm -rf "$iconset" "$stage"
mkdir -p "$iconset" "$stage/Contents/MacOS" "$stage/Contents/Resources"
for spec in '16 16x16' '32 16x16@2x' '32 32x32' '64 32x32@2x' '128 128x128' '256 128x128@2x' '256 256x256' '512 256x256@2x' '512 512x512' '1024 512x512@2x'; do
  set -- $spec
  sips -z "$1" "$1" "$root/icon.png" --out "$iconset/icon_$2.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$root/build/skyHAB.icns"

swift build -c release --package-path "$root/macos"
install -m 0755 "$root/macos/.build/release/skyHAB" "$stage/Contents/MacOS/skyHAB"
install -m 0644 "$root/packaging/SkyHAB.Info.plist" "$stage/Contents/Info.plist"
install -m 0644 "$root/build/skyHAB.icns" "$stage/Contents/Resources/skyHAB.icns"
embed_token_file="${SKYHAB_EMBED_TOKEN_FILE:-${SKYLAB_EMBED_TOKEN_FILE:-}}"
if [ -n "$embed_token_file" ]; then
  install -m 0600 "$embed_token_file" "$stage/Contents/Resources/app.token"
  echo "Warning: the app bundle contains a bearer token; distribute it as a secret." >&2
fi
printf '{"host":"%s","port":%s,"client":"%s"}\n' "$client_host" "$client_port" "$client_name" > "$stage/Contents/Resources/client.json"
codesign --force --sign - "$stage" >/dev/null
plutil -lint "$stage/Contents/Info.plist" >/dev/null

rm -rf "$output/skyHAB.app"
mv "$stage" "$output/skyHAB.app"
printf '%s\n' "$output/skyHAB.app"
