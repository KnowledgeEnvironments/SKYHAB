# Agentic CLI

`skyhabctl` is the supported command surface for scripts, operators, and supervised agents. It
connects to `skyhabd`; agents do not receive device credentials or speak adapter protocols.

## Start with identity and discovery

Use a unique viewer token for read-only automation. Keep it in the mode-0600 runtime token file or
provide `SKYHAB_TOKEN` through a protected process environment.

```sh
skyhabctl describe --json
skyhabctl resources --json
skyhabctl relationships --json
skyhabctl views --json
skyhabctl state --json
```

Successful JSON output is `{ "ok": true, "data": ... }`. Treat resource IDs, relationships,
server-provided actions, revisions, and presentation metadata as authoritative. Do not infer
topology or control capability from names, addresses, adapters, or prior observations.

## Read patterns

```sh
# Compact operational inventory
skyhabctl resources --json |
  jq '.data[] | {id, class, availability, severity, state_text}'

# Recent service events and action audit
skyhabctl events 25 --json
skyhabctl audit 25 --json

# Server-described UI/ownership model
skyhabctl view network --json
```

Prefer bounded queries and retain canonical values and timestamps when making decisions. An
offline, stale, reserved, or expected-offline resource is not automatically an incident.

## Mutations require separate authority

Read access does not imply permission to invoke `action`, metadata, pin, or photo commands. A
workflow that may mutate state should:

1. receive explicit operator authority for the particular action surface;
2. use a dedicated operator or admin identity rather than a viewer token;
3. inspect current state and the server-advertised action first;
4. invoke one explicit command with bounded parameters;
5. require the returned observed readback, not merely transport success;
6. review `audit` when outcome or timing is uncertain.

Do not automatically retry an uncertain state-changing request. `skyhabd` polls after controls and
reports success only when the requested field matches fresh observed state.

## Boundaries

- SkyWire is cleartext; use loopback, a trusted isolated LAN, or a narrow VPN.
- Never print tokens, auth files, secrets, camera stream responses, or production inventories.
- `camera.view` may return a credential-bearing URL and is inappropriate for general agent logs.
- Infrastructure remains read-only unless a narrowly documented server action says otherwise.
- For complete command coverage and error codes, see [`API.md`](../API.md).

Run `skyhabctl --help` for the installed command summary and `skyhabctl --version` when recording
automation diagnostics.
