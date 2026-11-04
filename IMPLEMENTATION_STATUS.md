# Implementation status

Release target: **1.1.0 naming and automation release**

Last reviewed: 2026-11-02

## Ready

- Portable C++20 SkyWire daemon and CLI with SQLite observations, history, events, and audit.
- Public process names are `skyhabd` and `skyhabctl`; legacy runtime paths and environment
  variables remain accepted for a low-risk migration.
- JSON-first CLI help, version reporting, resource aliases, and agentic-operation guidance.
- Hashed viewer/operator/admin authentication with last-good reload behavior.
- Revision-checked inventory, component metadata, pins, and revisioned asset photos.
- Explicit ontology, containment, lifecycle, importance, server-described views, and network
  relationships.
- Poll-after-action controls with generation-protected pending state in both Apple clients.
- Native macOS and iOS clients sharing the protocol, resource models, state machine, actions,
  metadata, history, and presentation projections.
- Specialized energy flow, UPS, air quality, solar ephemeris, alarm, lighting, climate,
  network chassis, compute topology, storage hierarchy, search, inventory, and offline views.
- Direct in-app RTSP playback without proxying or writing camera media to disk.
- Synthetic Aurora House demo inventory and static adapter for documentation and evaluation.
- Public-release privacy boundary: example config is fictional; runtime inventory, secrets,
  telemetry, and assets live outside the checkout.

## Known limitations

- Adapter subprocesses still use a constrained shell bootstrap rather than an argument-vector
  transport abstraction.
- There is no TLS, Unix-domain listener, event subscription stream, retention scheduler, or
  protocol-level token administration.
- Linux CI covers the portable backend; native Apple builds require macOS/Xcode.
- Storage has no SMART, scrub/resilver progress, or capacity forecasting.
- UI tests, adapter golden fixtures, fuzzing, and vintage-client acceptance remain future work.
- macOS RTSP requires an external ffmpeg executable. iOS keeps a deliberately old
  MobileVLCKit pin because newer tested builds regressed live playback.

The codebase is suitable for a source release and self-hosted evaluation. Operators remain
responsible for network isolation, credential hygiene, and device-specific acceptance tests.
