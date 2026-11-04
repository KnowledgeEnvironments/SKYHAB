# Adapter guide

An adapter turns one configured device into canonical observations and a deliberately small
action surface. Adapter names describe transport/integration, not resource class.

| Adapter | Purpose | Actions |
|---|---|---|
| `reachability.ping` | Generic availability | none |
| `shelly.*` | Lights and switched loads | power; brightness where supported |
| `venstar.local` | Thermostat state | mode, fan, heat/cool setpoints |
| `nut.ssh` | UPS telemetry | none |
| `mikrotik.routeros` | Router, switch, port, client, optional backup telemetry | none |
| `posix.ssh` | Host health; optional ZFS, filesystem, and Proxmox discovery | none |
| `enphase.envoy` | Solar production | none |
| `tesla.powerwall` | Battery and site power flow | none |
| `dyson.mqtt` | Air purifier and robot telemetry/control | device-specific narrow controls |
| `envisalink.tpi` | Alarm partition and keypad | Stay, Away, Disarm |
| `meshtastic.tcp` | Read-only radio/node telemetry | none |
| `site.ephemeris` | Local solar calculations | none |
| `tapo.rtsp` | Credential-resolved camera stream | view only |
| `demo.static` | Synthetic documentation/demo state | none |

## Configuration-driven discovery

RouterOS backup share, Wi-Fi parent mapping, POSIX ZFS/Proxmox discovery, and filesystem probes are
enabled by explicit config fields; no adapter behavior depends on undocumented, hard-coded site
identities. See the Aurora House example for static observations and the JSON schema for common
fields.

## SSH bootstrap

`nut.ssh` requires an explicit `config.ssh_user`; `nut_name` defaults to `ups@localhost`.
Non-router RouterOS resources likewise require `config.ssh_user`. Router-class RouterOS resources
and `posix.ssh` use the resource ID as a preconfigured OpenSSH host alias. Usernames, aliases,
targets, and command fragments are allow-listed before crossing the subprocess boundary.

## Adding an adapter

1. Validate every endpoint and any value that crosses a subprocess boundary.
2. Keep credentials in `SecretStore`; inventory contains references only.
3. Emit stable metric names, typed values, units, quality, and timestamps.
4. Add display metadata centrally in `telemetry.cpp` when a metric is reusable.
5. Keep mutation read-only unless the action can be narrowly verified by immediate readback.
6. Add fictional fixtures and failure tests; never capture a real device response verbatim.

The current subprocess bootstrap is intentionally constrained but remains a known refactor target.
