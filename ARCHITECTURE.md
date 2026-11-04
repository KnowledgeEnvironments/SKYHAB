# Architecture

skyHAB, the sky Habitat Automation Builder, uses one authoritative middle tier for a configured
habitat or site rather than letting each client speak every device protocol. That boundary keeps
secrets and policy in one place and gives native, scripted, agentic, and future clients the same
resource graph. The original deployment is named skyLAB; the architecture does not require that
name for other sites.

```text
Devices ── adapters ──> skyhabd ── SkyWire ──> skyHAB (macOS / iOS)
                            │                    skyhabctl
                            ├── inventory
                            ├── presentation catalog
                            ├── SQLite telemetry + audit
                            └── runtime secrets + asset photos
```

## Process model

`skyhabd` loads an inventory and presentation catalog, opens SQLite, starts polling lanes, and
accepts authenticated TCP clients. Every connection owns its decoder and identity; shared
stores are synchronized. Polling cadence is adapter-class based so fast controls, infrastructure,
and slow/discovery resources do not block one another.

`skyhabctl` is intentionally small. It is useful for health checks, JSON automation, and protocol
diagnostics; `API.md` is the source of truth for command coverage.

The Apple clients use the same Swift protocol and model sources. Platform shells differ, but
resource parsing, state reconciliation, history, metadata, and projection logic do not.

## Data planes

Inventory is desired identity and organization. Telemetry is observed state. The daemon never
writes telemetry into inventory and never recreates removed top-level resources from stale
state. Recognized child forms such as `/port/`, `/pool/`, `/vdev/`, `/disk/`, `/share/`, and
`/vm/` may be synthesized as discovered children of a configured owner.

Presentation is a third plane. The catalog chooses views, sections, selectors, renderers, and
ownership. The middle tier enriches raw observations with labels, units, display strings,
severity, freshness, and summary priority so clients agree on meaning.

## Control transaction

```text
user intent
   ↓
client pending overlay (generation N)
   ↓
ACTION.INVOKE ──> adapter command ──> immediate poll
                                      ↓
                         verify requested field/value
                                      ↓
                  authoritative state + audit result
```

The pending overlay is never an observation. A failed or mismatched readback removes it and
restores the observed presentation. Late completion from generation N cannot clear generation
N+1.

## Resource and relationship graph

Containment is explicit through `parent`; the server computes `children`, `ancestors`, and
`depth`. Network topology is separate and comes only from `RELATIONSHIP.LIST`, including exact
port endpoints. Cross-domain appearances are references to one canonical resource, never
duplicate identity.

## Authentication and secrets

Tokens map an exact client identity to viewer, operator, or admin. Authentication data and
device secrets are external mode-0600 files. Inventory stores credential references, not values.
The cleartext protocol assumes loopback, a trusted LAN, or a narrow VPN.

## Camera path

An authenticated client requests `CAMERA.STREAM`; the daemon resolves credentials and returns a
complete RTSP URL. Media then flows directly from camera to client. macOS decodes through an
in-memory ffmpeg pipe; iOS uses MobileVLCKit over RTSP/TCP. The URL must never be logged.

## Failure model

- Each poll is independent and produces quality/freshness metadata.
- Authentication reload retains last-good state on malformed or unreadable files.
- SkyWire transactions are serialized per connection and have bounded deadlines.
- Uncertain state-changing requests are not automatically replayed.
- Current-state rendering is cached briefly and invalidated on record, while history remains
  durable in SQLite.
