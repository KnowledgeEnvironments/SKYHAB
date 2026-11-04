# Configuration

skyHAB ships a fictional, runnable site called Aurora House. A production installation uses
external runtime configuration so a source checkout can remain public and replaceable. The
canonical runtime path is `Application Support/skyHAB`; a site's display name remains independent.
The macOS installer migrates the legacy `Application Support/skyLAB` path during upgrade.

## Create the runtime directory

```sh
mkdir -p "$HOME/Library/Application Support/skyHAB"
cp inventory/inventory.example.json \
  "$HOME/Library/Application Support/skyHAB/inventory.json"
cp presentation/views.json \
  "$HOME/Library/Application Support/skyHAB/views.json"
chmod 600 "$HOME/Library/Application Support/skyHAB/"*.json
```

Edit the copies, not the checked-in example. Start with a small read-only inventory and add one
adapter family at a time.

## Site identity

`site.pretty_name` is shown in the clients. `site.subtitle` is descriptive text for About and
connection surfaces. `site.timezone` is an IANA identifier. Site coordinates, when needed by the
ephemeris adapter, belong in that adapter's external inventory config and should be treated as
private.

## Endpoints and credentials

Endpoints contain routable host/port facts. `credential_refs` maps adapter fields to names in the
external secrets store. For example:

```json
{
  "credential_refs": {"username": "garden_camera_user", "password": "garden_camera_password"}
}
```

The secrets file stores values under those names and must be mode 0600. Environment variables of
the form `SKYHAB_SECRET_<NORMALIZED_REFERENCE>` can provide ephemeral overrides; the legacy
`SKYLAB_SECRET_` prefix remains accepted in 1.1.

## Presentation

The example catalog is deliberately generic. Keep its stable view IDs if you want specialized
native renderers, but titles, sections, selectors, order, and resource ownership are site data.
The overview sections `daylight`, `air-quality`, `power`, `security`, and `infrastructure` feed
cross-platform projections.

## Validation

The repository tests validate the public example. For a private inventory, also check unique IDs,
parent existence, relationship endpoints, duplicate pins, credential-reference names, and JSON
schema conformance before restarting the daemon.

Never paste a production inventory into an issue or CI artifact. Reduce a bug to a fictional
fixture using RFC 5737 addresses.
