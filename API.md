# SkyWire command and record API

Implementation note: the command descriptions below include the intended V1 surface.
Currently implemented commands are `PING`, `AUTH`, `SERVICE.DESCRIBE`, `CLASS.LIST`,
`RESOURCE.LIST`, `RESOURCE.GET`/`RESOURCE.DESCRIBE`, `STATE.GET`, `METRIC.QUERY`,
`ACTION.INVOKE`, `AUDIT.LIST`, `EVENT.LIST`, `INVENTORY.GET`, `INVENTORY.PATCH`,
`METADATA.PATCH`, `COMPONENT.PATCH`, `PIN.SET`, `VIEW.LIST`, `VIEW.DESCRIBE`,
`RELATIONSHIP.LIST`, `ASSET.PHOTO.GET`, `ASSET.PHOTO.SET`, `ASSET.PHOTO.DELETE`, and
`CAMERA.STREAM`, and `STORAGE.FILES`. Other named commands are
reserved design, not claims about the live daemon.

This is the normative V1 command catalog. All arguments are named typed values;
order is insignificant. Required role is shown in parentheses.

## Session and discovery

- `VERSION` (unauthenticated): negotiate `major`, `minor`, and repeated features.
- `PING` (unauthenticated): returns server time and optional echoed value.
- `AUTH` (unauthenticated): authenticate `client` and `token`.
- `SERVICE.DESCRIBE` (viewer): server ID, site, timezone, versions, limits, links,
  and enabled adapters.
- `CLASS.LIST` / `CLASS.GET` (viewer): semantic device classes and default
  presentation metadata.
- `RESOURCE.LIST` / `RESOURCE.GET` (viewer): filter by class, parent, health,
  segment, location, capability, or changed-since.
- `RESOURCE.DESCRIBE` (viewer): descriptor, metric definitions, actions, argument
  types/ranges/enums, polling/freshness, and presentation hints.
- `RELATIONSHIP.LIST` (viewer): explicit inventory relationships such as network links;
  returns ID, kind, source, target, optional endpoint-local `source_port` and `target_port`,
  optional label, and optional bit-rate capacity. Port names are explicit inventory facts;
  clients must not infer endpoint pairs from addresses or interface naming.

Current implementation notes: `SERVICE.DESCRIBE` returns service/protocol versions,
inventory/presentation revisions, and the configured site's ID, pretty name, subtitle, and
timezone. `CLASS.LIST` is implemented; `CLASS.GET` is reserved.
`RESOURCE.LIST` currently returns the full resolved list without server-side filters.
`RESOURCE.GET` and `RESOURCE.DESCRIBE` accept `id` and currently return configured top-level
devices; discovered children are obtained from `RESOURCE.LIST`.

## State, metrics, and events

- `STATE.GET` (viewer): current typed observations for one resource or a filter.
- `METRIC.QUERY` (viewer): resource, metric, start, end, resolution, and limit;
  returns raw or rollup records.
- `EVENT.LIST` (viewer): persisted events by sequence/time/topic/resource.
- `EVENT.WATCH` (viewer): subscribe by topic/resource and optional resume sequence.
- `EVENT.UNWATCH` (viewer): cancel a subscription.
- `CAMERA.STREAM` (viewer): accepts a camera `resource` and returns `scheme: rtsp`
  and the complete credential-bearing `url`. The client passes that URL directly to its
  embedded RTSP decoder. This response is sensitive and intentionally exposes the device
  credential to authenticated SkyWire viewers.
- `STORAGE.FILES` (viewer): accepts `resource` and an optional `limit` capped at 100.
  A RouterOS resource can expose one configured backup-share child. It returns `available`, a normalized
  operator-facing `message`, and newest-first file records containing `path`, `name`,
  RouterOS `modified`, `modified_at_ms`, `age`, and, where reported, `size_bytes` and
  `display_size`. An unmounted backup disk is a successful unavailable listing, not a
  fabricated empty directory. Files are observations, not inventory resources.

Current implementation notes: `STATE.GET` optionally accepts `resource`. `METRIC.QUERY`
requires `resource`, `metric`, `start_ms`, and `end_ms`, with optional `limit`; resolution
rollups are reserved. `EVENT.LIST` is implemented. `EVENT.WATCH` and `EVENT.UNWATCH` remain
reserved.

Current observation records contain `resource`, `metric`, `value`, `unit`, `quality`, and
`observed_at_ms`, plus middle-tier display fields. `source` and `stale_after` remain reserved
additive fields.

## Actions

- `ACTION.INVOKE` (operator): resource, action, idempotency key, optional expected
  state revision, followed by descriptor-defined parameters.
- `ACTION.GET` (viewer): retrieve an action result and audit ID.
- `AUDIT.LIST` (admin): retrieve immutable action records in reverse order,
  including actor, resource, action, parameters, result, and timestamp.

V1 action IDs are `power.on`, `power.off`, `brightness.set`,
`thermostat.mode.set`, `thermostat.fan.set`, and `thermostat.setpoints.set`.
`thermostat.fan.set` accepts `fan` as `auto` or `on`. A successful action means
the requested post-state was read back. Transport acceptance without matching
post-state returns `verification_failed`.

Dyson resources additionally advertise `dyson.fan_speed.set`, `dyson.auto.set`,
`dyson.night.set`, `dyson.oscillation.set`, `vacuum.start`, `vacuum.pause`,
`vacuum.resume`, and `vacuum.return_to_dock`. Clients must render only actions present in
the resource descriptor. Dyson control is local MQTT; credentials never cross SkyWire.

The read-only `site.ephemeris` resource publishes canonical `site_address`,
`site_coordinates`, numeric `latitude`/`longitude`, `sunrise`, `sunset`,
`daylight`, `solar_phase`, `solar_progress`, `solar_altitude`, `daylight_duration`,
`day_progress`, `sunrise_day_progress`, `sunset_day_progress`, and `next_transition`
observations. The three civil-day progress values let clients draw a normalized 24-hour
night/day/night instrument without parsing formatted times. Calculation is local from
inventory coordinates and the server's site timezone; clients do not contact a weather or
astronomy service.

Twilight is published at the conventional solar-center thresholds as paired local clock
and civil-day progress observations: `civil_dawn`/`civil_dusk` at −6 degrees,
`nautical_dawn`/`nautical_dusk` at −12 degrees, and
`astronomical_dawn`/`astronomical_dusk` at −18 degrees. Each clock metric has a matching
`*_day_progress` metric for portable visualization.

The read-only `meshtastic.tcp` adapter uses Meshtastic's framed TCP client stream on port
4403 and completes a nonce-matched configuration snapshot before publishing observations.
It exposes `firmware_version`, `hardware_model`, `mesh_role`, `node_count`,
`expected_node_count`, `recent_node_count` (heard within 24 hours), `direct_node_count`,
`mqtt_node_count`, `last_mesh_activity_age`, `local_node_name`, `local_node_short_name`,
`local_node_id`, `reboot_count`, `minimum_app_version`, `platform_environment`,
`radio_uptime`, `radio_snr`, `battery_level`, `voltage`, `channel_utilization`, and
`air_utilization` when supplied by the radio. A poll stores summary telemetry only: it does
not persist the node database, positions, channel material, or message payloads. Meshtastic
send/configuration actions are not advertised.

Current `ACTION.INVOKE` arguments are `resource`, `action`, and optional JSON-string
`parameters`. Descriptor-advertised actions enforce operator role. Idempotency keys,
expected-state revisions, and `ACTION.GET` remain reserved.

## Inventory

- `INVENTORY.GET` (viewer): current revision and normalized records.
- `INVENTORY.PATCH` (admin): expected revision, device ID, and an allowlisted set
  of fields including pretty name, comment, location, enabled, labels, and poll
  overrides.
- `INVENTORY.ADD` (admin): add a schema-valid configured device.
- `INVENTORY.REMOVE` (admin): disable by default; physical deletion requires the
  exact canonical ID as confirmation.
- `INVENTORY.RELOAD` (admin/local): validate and adopt an externally edited file.

Every implemented mutation returns the new revision. Emitting `inventory.changed` is part
of the reserved subscription design. Secrets, live state, and metric values are invalid
inventory fields.

Current implementation notes: `INVENTORY.GET`, revision-checked `INVENTORY.PATCH`,
`METADATA.PATCH`, `COMPONENT.PATCH`, and `PIN.SET` are live. `METADATA.PATCH` is the preferred
generic metadata route and accepts `pretty_name`, `comment`, `asset_tag`, `notes`, `room`, and `groups` for both
configured devices and discovered children. Inventory add/remove/reload and emitted
`inventory.changed` subscriptions remain reserved.

Asset photos are separate from the inventory envelope. `ASSET.PHOTO.GET resource s<id>`
returns MIME type and base64 bytes. Operator-only `ASSET.PHOTO.SET` requires an expected
inventory `revision`, `mime` (`image/jpeg` or `image/png`), and base64 `data` no larger than
256 KiB. `ASSET.PHOTO.DELETE` requires resource and revision. Set/delete advance the
inventory revision; resource descriptors expose only `photo_available`. Files are mode 0600
under the runtime database directory's `assets/` folder.

## Token administration

- `TOKEN.CREATE`, `TOKEN.LIST`, `TOKEN.REVOKE`, and `TOKEN.ROTATE` require a local
  administrator connection. A new token is returned exactly once.

## Errors

Stable error codes include:

| Code | Meaning |
|---|---|
| `bad_request` | malformed command or typed argument |
| `unsupported_version` | no compatible protocol major |
| `unauthenticated` | authentication is required or failed |
| `forbidden` | actor role cannot perform the operation |
| `not_found` | command, resource, metric, or action does not exist |
| `conflict` | stale inventory/state revision or duplicate identity |
| `unavailable` | target or required transport is unavailable |
| `timeout` | operation exceeded its deadline |
| `verification_failed` | write was accepted but post-state did not match |
| `rate_limited` | retry after the returned interval |
| `internal` | unexpected server failure with an opaque correlation ID |

## CLI mapping

`skyhabctl` exposes these commands:

```text
skyhabctl status|state|ping|describe|resources|devices|relationships|classes|views|audit|events [--json]
skyhabctl view VIEW_ID [--json]
skyhabctl files RESOURCE [LIMIT] [--json]
skyhabctl action RESOURCE ACTION [PARAMETERS_JSON] [--json]
skyhabctl rename|comment|asset-tag|notes|room|group RESOURCE VALUE [--json]
skyhabctl pin|unpin RESOURCE [--json]
skyhabctl photo-get RESOURCE OUTPUT_FILE [--json]
skyhabctl photo-set RESOURCE JPEG_OR_PNG_FILE [--json]
skyhabctl photo-delete RESOURCE [--json]
```

`--help` and `--version` are offline. `--host`, `--port`, `--client`, and `--token` select the connection. `--json` wraps success
as `{ "ok": true, "data": ... }`; without it, arrays are emitted one JSON record per line.
`skyhabctl` returns 0 on success and 7 for usage, server, authentication, or
transport failures; finer stable exit-code mapping remains future work.

The CLI does not yet provide hostname resolution, single-resource or metric-history
convenience commands, or arbitrary multi-field/component patch commands.
Agents should use the commands above with `--json` and `jq`; these are CLI limitations, not
limitations of the corresponding SkyWire APIs.
# Presentation metadata and change tracking

Numeric state and trend rows retain canonical `value` and `unit` fields and also carry
`display_value`, `display_unit`, and `display_decimals`. Clients should display the latter
but graph or calculate with the canonical fields. This keeps byte, watt, energy, ratio,
runtime, and percentage formatting consistent across modern and vintage clients.

State rows also carry `label`, `display_text`, `display_priority`, `visibility`
(`summary`, `detail`, or `internal`), `kind`, `severity`, and, where applicable,
`meaning` such as `charging`, `discharging`, `importing`, or `exporting`. Resource
descriptors include `state_text`, aggregate `severity`, and an ordered four-item
`summary`. A small client can therefore render useful cards without understanding
device-specific metric names.

Resources also expose `availability` as `online`, `offline`, or `unknown`. Non-embedded
offline resources advertise `presentation.visibility: offline`; clients should omit them
from normal views and provide a dedicated offline list. Faulted or degraded infrastructure
is not classified as merely offline and remains visible for attention.

`RESOURCE.LIST` descriptors include `pretty_name`, `comment`, `asset_tag`, `notes`,
`photo_available`, `room`, `groups`, `address`, `pinned`, and `pin_order`. Discovered
`network-port` resources are children of their switch;
general clients should hide them from ordinary resource lists and render them through a
port-map view. Storage vdevs and member disks follow the same rule. Their
`presentation.visibility` is `embedded`, and `presentation.container` identifies the
parent visualization.

Top-level descriptors also separate identity from monitoring transport:

- `roles` lists the functions performed by the resource;
- `lifecycle` is `active`, `reserved`, `expected-offline`, `development`, or `retired`;
- `importance` is `critical`, `important`, `normal`, or `accessory`;
- `presentation_home` names the one view responsible for full rendering;
- `parent` expresses canonical containment or hosting.

The middle tier resolves relationships and additionally returns `children`, `ancestors`,
and `depth`. Clients must not infer containment from resource IDs, addresses, group order,
or adapter type. Discovered ports, pools, shares, vdevs, and disks participate in the same
relationship graph.

Clients must not treat reserved or expected-offline resources as availability incidents.
They belong in administrative inventory unless a view explicitly requests them.

`EVENT.LIST limit s100` returns durable metric changes. `PIN.SET resource s<id> pinned
s<true|false> revision s<n>` changes inventory-backed priority. `INVENTORY.PATCH` accepts
generic metadata changes including `pretty_name`, `comment`, `asset_tag`, `notes`, `room`,
and `groups` using
optimistic inventory revisions.

## Server-described presentation

`VIEW.LIST` returns the ordered navigation catalog. `VIEW.DESCRIBE id s<view-id>` returns
the client-neutral composition for one view: sections, priorities, layouts, resource queries,
renderer recommendations, embedded-child behavior, and semantic fallbacks. The catalog is
loaded from `presentation/views.json` and advertised as `skylab.presentation/1` by
`SERVICE.DESCRIBE`.

Clients retain control of native widgets and exact geometry, but should follow the server's
canonical view ownership and hierarchy. Unknown renderers fall back to generic rows, port
tables, indented trees, or metric summaries.

`METADATA.PATCH resource s<id> revision s<n> changes s<json>` is the unified metadata API.
For inventory devices it updates the device record; for discovered ports, pools, arrays,
disks, and VMs it writes a JSON-backed override under the owning device's
`component_overrides`. Operator-editable fields are `pretty_name`, `comment`, `asset_tag`,
`notes`, `room`, and `groups`.

## Alarm resources and actions

An `envisalink.tpi` alarm advertises `alarm.arm_stay`, `alarm.arm_away`, and `alarm.disarm`;
all require the operator role. Invoke them through `ACTION.INVOKE` without credential
parameters. The server returns verification status and resulting transition only.
When `mandatory_bypass_zone` is configured, `alarm.disarm` restores that bypass after confirming
the disarmed partition and reports the verified `disarmed-ready` transition. It never resends the
bypass sequence while the panel already indicates Bypass, because keypad bypass entry is a toggle.

Alarm state includes `partition_mode`, `armed`, `ready`, `alarm`, `fire`, `bypass`,
`trouble`, `ac_power`, `low_battery`, `alarm_memory`, `chime`, `open_zones`,
`open_zone_count`, `keypad_line1`, `keypad_line2`, `keypad_beep`, and `last_event`.
The keypad rows are actual fixed-width panel LCD text and should be rendered monospaced.
Inactive burglar alarm, fire alarm, trouble, and low-battery booleans are detail-only.
They become summary-visible only while active, with critical or warning severity as applicable.

## Associated network clients

Wi-Fi stations are embedded `network-client` children of their AP. State includes hostname,
IP, MAC, managed radio, SSID, band, signal, and activity when RouterOS supplies them. The owning
router joins registration-table MACs to DHCP leases. Clients keep these collapsed inside the AP
chassis rather than presenting them as inventory devices.

For switches, `network-client` children are emitted only when one non-local MAC is the sole
learned station on a non-trunk/non-bridge edge port. The `physical_port` metric identifies
that attachment. Fabric, VLAN, AP fan-out, and virtualization paths are deliberately omitted.
