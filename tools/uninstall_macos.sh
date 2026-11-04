#!/bin/sh
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

set -eu
launchctl bootout "gui/$(id -u)/com.skyhab.skyhabd" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.skylab.skylabd" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.skyhab.skyhabd.plist"
rm -f "$HOME/Library/LaunchAgents/com.skylab.skylabd.plist"
echo "Stopped and removed the launch agent. Runtime data was retained."
