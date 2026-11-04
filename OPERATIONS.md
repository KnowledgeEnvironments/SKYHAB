# Operations and security

## Build

```sh
cmake --preset release
cmake --build --preset release
ctest --test-dir build/release --output-on-failure
swift test --package-path macos
```

For iOS, install the pinned CocoaPods dependencies and build the workspace:

```sh
bundle install
bundle exec pod install --project-directory=ios
xcodebuild -workspace ios/skyHAB.xcworkspace -scheme skyHAB -sdk iphonesimulator \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Runtime layout on macOS

`tools/install_macos.sh` installs the daemon and CLI under
`~/Library/Application Support/skyHAB/`, creates an empty secrets file and auth store, and copies
the fictional example inventory only when no external inventory exists. It binds loopback by
default. The installed programs and launch agent are `skyhabd`, `skyhabctl`, and
`com.skyhab.skyhabd`. On upgrade, the installer atomically moves a legacy
`Application Support/skyLAB` directory to the canonical skyHAB path; it refuses to guess if both
directories already exist.

Useful overrides:

```sh
SKYHAB_INVENTORY_PATH=/secure/path/inventory.json \
SKYHAB_VIEWS_PATH=/secure/path/views.json \
SKYHAB_DB_DIR=/secure/path/runtime \
SKYHAB_BIND_ADDRESS=127.0.0.1 \
tools/install_macos.sh
```

The install script never overwrites an existing inventory or presentation catalog. Legacy
`SKYLAB_*` forms remain accepted in 1.1 for compatibility.

## Authentication

Manage tokens with `tools/manage_tokens.py`. Give each client a unique identity and least-
privilege role. Token files, auth hashes, and device secrets should be readable only by the
service account.

Do not embed a token in a distributed app. `tools/build_shared_skyhab.sh` builds without one by
default. A private deployment may explicitly set `SKYHAB_EMBED_TOKEN_FILE`; the resulting bundle
is then a secret-bearing credential artifact.

## Threat model

SkyWire has no TLS. Authentication prevents anonymous access but does not hide tokens or data
from an on-path observer. The deployment transport must provide confidentiality and isolation:
use loopback, an isolated trusted IoT VLAN, or an authenticated, tightly scoped tunnel to the
host. Do not bind all interfaces or forward port 3636 from the public internet.

Camera stream discovery returns a credential-bearing RTSP URL to an authenticated client. Do not
log, proxy, paste, or capture that response. Media is direct from device to client.

## Backups

Back up these external runtime assets together:

- inventory and presentation JSON;
- authentication and secrets files;
- SQLite database, using SQLite's online backup mechanism or a stopped service;
- the adjacent `assets/` directory containing resource photos.

Telemetry can be recreated; inventory metadata and assets generally cannot.

## Observability

Standard output reports the listener and version. Standard error reports adapter and protocol
failures but must never include tokens, secret-file contents, or camera URLs. Repeated poll errors
are rate-limited. Use the CLI with `--json` for scripted checks.

## Production acceptance

Before enabling actions, verify each adapter read-only, confirm endpoint identity, use an
idempotent target state where possible, and inspect the immediately returned observation time and
value. High-consequence controls require an operator physically present for first acceptance.
