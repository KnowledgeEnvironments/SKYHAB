#!/bin/sh
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
private_dir="$tool_dir/private"
private_home="$private_dir/home"
binary="$tool_dir/bin/opendyson"

if [ ! -x "$binary" ]; then
  echo "opendyson is not installed at $binary" >&2
  echo "Follow config-tools/opendyson/README.md to restore the pinned tool." >&2
  exit 1
fi

umask 077
mkdir -p "$private_home"
chmod 700 "$private_dir" "$private_home"

if [ "${1:-}" = "capture" ]; then
  output="$private_dir/devices.yaml"
  HOME="$private_home" "$binary" devices > "$output"
  chmod 600 "$output"
  echo "Saved credential-bearing device data to $output"
  exit 0
fi

HOME="$private_home" exec "$binary" "$@"
