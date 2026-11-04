#!/usr/bin/env python3
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
catalog = json.loads((root / "presentation/views.json").read_text())
inventory = json.loads((root / "inventory/inventory.example.json").read_text())

assert catalog["schema"] == "skylab.presentation/1"
assert isinstance(catalog["revision"], int) and catalog["revision"] >= 1
views = catalog["views"]
ids = [view["id"] for view in views]
assert len(ids) == len(set(ids))
assert ids == ["overview", "habitat", "security", "lighting", "climate", "energy", "network", "compute", "storage", "offline", "inventory"]
assert [view["priority"] for view in views] == sorted(view["priority"] for view in views)

known_resources = {device["id"] for device in inventory["devices"]}
known_groups = {group for device in inventory["devices"] for group in device["groups"]}
known_classes = {device["class"] for device in inventory["devices"]}
renderers = set()
for view in views:
    assert view["title"] and view["icon"] and isinstance(view["sections"], list)
    section_ids = [section["id"] for section in view["sections"]]
    assert len(section_ids) == len(set(section_ids))
    for section in view["sections"]:
        assert section["layout"] and isinstance(section["items"], list)
        for item in section["items"]:
            assert ("resource" in item) != ("query" in item)
            if "resource" in item:
                assert item["resource"] in known_resources
            query = item.get("query", {})
            if "group" in query:
                assert query["group"] in known_groups
            if "class" in query:
                assert query["class"] in known_classes or query["class"] in {"storage-share"}
            renderers.add(item["renderer"])

for renderer in {"energy-flow", "switch-port-map", "storage-tree", "cluster-tree", "solar-trend"}:
    assert renderer in renderers

print("presentation contract tests passed")
