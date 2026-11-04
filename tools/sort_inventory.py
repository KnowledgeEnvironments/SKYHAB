#!/usr/bin/env python3
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

"""Deterministically order the inventory device array without changing records."""

import json
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "inventory/inventory.json"
data = json.loads(path.read_text())
data["devices"] = sorted(data["devices"], key=lambda device: device["id"])
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
