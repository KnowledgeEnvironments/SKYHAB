#!/usr/bin/env python3
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

import ipaddress
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
inventory = json.loads((root / "inventory/inventory.example.json").read_text())

assert inventory["schema_version"] == 2
assert inventory["revision"] >= 1
assert inventory["site"]["pretty_name"] == "Aurora House"
assert inventory["site"]["subtitle"]

required = {
    "id", "class", "adapter", "pretty_name", "comment", "enabled", "location",
    "room", "groups", "roles", "lifecycle", "importance", "presentation_home",
    "segment", "labels", "endpoints", "credential_refs", "config", "component_overrides",
}
devices = inventory["devices"]
ids = [device["id"] for device in devices]
assert len(ids) == len(set(ids))
assert ids == sorted(ids)
assert all(required <= set(device) for device in devices)
assert all(device["lifecycle"] in {"active", "reserved", "expected-offline", "development", "retired"} for device in devices)
assert all(device["importance"] in {"critical", "important", "normal", "accessory"} for device in devices)

# Public examples may only use IETF documentation address blocks.
allowed = [ipaddress.ip_network(value) for value in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")]
for device in devices:
    for endpoint in device["endpoints"]:
        address = ipaddress.ip_address(endpoint["host"])
        assert any(address in network for network in allowed), (device["id"], address)

relationships = inventory["relationships"]
assert len({link["id"] for link in relationships}) == len(relationships)
assert all(link["source"] in ids and link["target"] in ids for link in relationships)
assert all(link.get("source_port") and link.get("target_port") for link in relationships if link["kind"] == "network-link")
assert all(pin["resource"] in ids for pin in inventory["pins"])

print("example inventory contract tests passed")
