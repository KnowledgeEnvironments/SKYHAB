#!/bin/sh
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
daemon="$root/build/debug/skyhabd"

if [ ! -x "$daemon" ]; then
  echo "build/debug/skyhabd is missing; run cmake --preset debug and cmake --build --preset debug" >&2
  exit 1
fi

mkdir -p "$root/var"
exec "$daemon" \
  --inventory "$root/inventory/inventory.example.json" \
  --database "$root/var/demo.sqlite3" \
  --views "$root/presentation/views.json" \
  --bind 127.0.0.1 \
  --port 3636 \
  --token skyhab-demo-local-only
