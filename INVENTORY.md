# Inventory specification

Inventory is a revisioned JSON document that describes configured identity and intent. The
public example is `inventory/inventory.example.json`; a real deployment should copy it outside
the checkout.

## Envelope

```json
{
  "schema_version": 2,
  "revision": 1,
  "updated_at": "2026-10-31T00:00:00Z",
  "site": {
    "id": "aurora-house",
    "pretty_name": "Aurora House",
    "subtitle": "Habitat & systems laboratory",
    "timezone": "America/Los_Angeles"
  },
  "segments": [],
  "devices": [],
  "relationships": [],
  "pins": []
}
```

The normative machine-readable shape is `inventory/schema-v2.json`.

## Device identity

Each device has a stable lowercase `id`, semantic `class`, transport `adapter`, human-authored
name/comment, organization fields, endpoint list, credential references, adapter config, and
component overrides. IDs survive address, room, and name changes.

Do not put secrets in endpoints, comments, labels, notes, or adapter config. Use
`credential_refs` to point at keys in the runtime secrets file.

## Organization fields

- `groups`: many-to-many operational association.
- `roles`: capabilities or responsibility.
- `parent`: canonical containment.
- `room` and `location`: physical placement.
- `lifecycle`: `active`, `reserved`, `expected-offline`, `development`, or `retired`.
- `importance`: `critical`, `important`, `normal`, or `accessory`.
- `presentation_home`: the one canonical full-detail view.

These fields are independent. A UPS can be physically contained by a rack host, belong to power
and infrastructure groups, and have Energy as its presentation home.

## Discovered components

Adapters may emit state for recognized child IDs:

- `owner/port/name` and `owner/client/id`
- `owner/pool/name`, with `/vdev/name` and `/disk/name`
- `owner/share/name`
- `owner/vm/id`

The daemon synthesizes these children only when their owner remains configured. Human-facing
metadata belongs in the owner's `component_overrides`, so discovery cannot overwrite it.

## Relationships

Containment and network links are distinct. A physical network relationship includes `source`,
`target`, and exact `source_port`/`target_port` values. Clients never infer a trunk from address,
name, port order, or comments.

## Mutation

Metadata and pins use optimistic concurrency. A client sends the revision it read; the daemon
writes atomically only if that revision is current, increments `revision`, and updates
`updated_at`. Asset photos use the same revision contract but live in the runtime asset store,
not inside JSON.

Back up inventory before administrative edits. On conflict, fetch canonical state and merge
rather than replaying a stale whole document.
