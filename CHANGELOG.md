# Changelog

All notable changes to skyHAB are documented here.

## 1.1.0 — 2026-10-31

- Removed site-specific bootstrap defaults and tightened validation at adapter subprocess boundaries.
- Standardized public attribution, dependency provenance, and the isolated-network threat model.
- Clarified that skyHAB is the software suite and skyLAB is the original home installation.
- Renamed the public daemon and CLI to `skyhabd` and `skyhabctl`.
- Made `Application Support/skyHAB` and `Logs/skyHAB` canonical, with a guarded installer
  migration from the legacy skyLAB directories and read fallbacks for older client files.
- Added compatibility aliases for legacy executable names, tokens, and environment variables.
- Added offline CLI help/version output, a `resources` alias, strict unknown-command handling, and
  guidance for supervised agent and automation use.
- Renamed the launch agent and improved fresh-clone build/install discovery.

## 1.0.0 — 2026-10-31

- First public source release of the sky Habitat Automation Builder.
- C++20 middle tier, SkyWire protocol, CLI, SQLite telemetry/audit, and adapter suite.
- Native shared-state macOS, iPhone, and iPad clients.
- Server-described overview, habitat, security, lighting, climate, power, network, compute,
  storage, offline, and inventory experiences.
- Synthetic Aurora House demo, public documentation, CI, MIT license, and privacy-safe runtime
  configuration boundary.
