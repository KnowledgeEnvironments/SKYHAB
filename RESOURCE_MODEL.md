# Resource model

skyHAB models a configured site as resources, observations, containment, and relationships.

## Orthogonal dimensions

| Field | Meaning | Example |
|---|---|---|
| `class` | What the resource is | `router`, `ups`, `storage-pool` |
| `adapter` | How it is reached | `mikrotik.routeros`, `nut.ssh` |
| `roles` | What it does | `gateway`, `protected-power` |
| `groups` | Operational association | `core-infrastructure`, `energy` |
| `parent` | Canonical containment | host → VM; pool → disk |
| `lifecycle` | Expected operational state | `active`, `expected-offline` |
| `importance` | Operational consequence | `critical`, `accessory` |
| `presentation_home` | Full-detail owner view | `network`, `storage` |

No field is derived from another. In particular, adapters do not define classes and addresses do
not define topology.

## Canonical home and references

A resource has one full-detail home. Other views may reference its status without duplicating
the whole card. This keeps overview, power, compute, and storage consistent when one physical
system spans several domains.

## Containment

The inventory stores `parent`; the daemon resolves `children`, `ancestors`, and `depth`. Embedded
ports, storage members, and associated clients render inside their owner rather than as loose
operational cards.

## Lifecycle and incidents

Only unexpectedly unhealthy active resources are incidents. Reserved, expected-offline,
development, and retired resources remain searchable and inventoried without polluting the
review/offline experience.

Within a category or containment level, confirmed offline resources sort last. Pins, explicit
view priority, and parent/child topology take precedence over availability.

## Presentation catalog

`presentation/views.json` declares ordered views and sections. An item selects one resource or
queries by class, group, lifecycle, availability, severity, pin, or presentation home. Renderer
names are portable hints; native clients own geometry and controls.

The Aurora House catalog is an example, not a required taxonomy. A site can rename sections and
choose different group selectors without changing protocol or client code.

## State model

An observation carries resource, metric, typed value, unit, quality, and timestamp. The middle
tier adds display label, priority, visibility, severity, freshness, and formatted value. Clients
render these canonical hints and keep pending intent separate.
