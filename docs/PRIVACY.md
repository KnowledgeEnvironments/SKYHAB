# Privacy and release safety

A habitat inventory is a compact map of a person's life. Names, rooms, coordinates, camera
placement, security policy, private addresses, hardware, absence patterns, and telemetry can be
sensitive even when no password is present.

## Never commit

- production inventory or onboarding notes;
- private IP plans, DNS names, MAC addresses, SSIDs, coordinates, street addresses, or VPN routes;
- tokens, auth stores, device secrets, SSH material, or credential-bearing URLs;
- SQLite/WAL files, logs, asset photos, crash reports, or derived telemetry;
- screenshots from a real deployment;
- signed/private app bundles containing endpoint or token configuration.

The ignore rules are defense in depth, not permission to keep secrets in the repository tree.
Prefer external runtime directories.

## Public fixtures

Use fictional names and only RFC 5737 IPv4 ranges (`192.0.2.0/24`, `198.51.100.0/24`, and
`203.0.113.0/24`). Synthetic telemetry must not be transformed from real readings if it could
retain identifying patterns.

## Before publishing

1. Scan the complete candidate tree, including generated assets and app resources.
2. Search every commit that will be pushed, not only the working tree.
3. Build screenshots from the synthetic demo.
4. Inspect binaries and bundles for embedded JSON, token files, paths, and strings.
5. Start a fresh public history when the private development history contains site data.

Run `tools/audit_public_tree.sh` from the clean candidate checkout. It is a release guard, not a
substitute for reviewing prose, images, generated bundles, and the exact history being pushed.

Deleting a file in a later commit does not remove it from Git history. This project intentionally
publishes from a clean, squashed root rather than exposing its private development history.
