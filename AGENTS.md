# Maintainer guide

This file applies to the entire repository. Read `IMPLEMENTATION_STATUS.md` before changing
behavior and `docs/PRIVACY.md` before adding fixtures, logs, screenshots, or configuration.

## Identity and boundaries

- skyHAB is the released software suite—the sky Habitat Automation Builder. `skyhabd` is its
  authoritative middle tier, `skyhabctl` is its CLI, and the native Apple client is also branded
  skyHAB. skyLAB is the proper name of the original home installation, not a generic subsystem.
- Keep adapters focused on canonical observations and actions. Labels, display values,
  freshness, severity, and summaries belong in the presentation layer where possible.
- `class` says what a resource is; `adapter` says how it is reached. Containment, roles,
  groups, room, lifecycle, importance, and presentation ownership are independent.
- The server resolves children, ancestors, and depth. Clients must not infer topology from
  IDs, addresses, adapter type, or array order.
- Network fabric comes only from explicit relationships with source and target ports.
- Authoritative observations, pending desired state, and rendered display state are distinct.
  Never overwrite an observation to simulate success.

## Privacy and credentials

- The repository is public. Never commit real inventories, addresses, coordinates, hostnames,
  room names, asset tags, notes, telemetry databases, tokens, credentials, camera URLs, or
  screenshots of a live site.
- Public examples use only RFC 5737 address blocks and fictional identity.
- SkyWire is cleartext and always requires authentication. Bind loopback by default.
- Camera stream responses may contain credentials. Never log them.
- Runtime secrets belong in mode-0600 files outside the checkout.

## Safety

- Controls are explicit, audited, and followed by a poll. Success requires observed readback.
- Network configuration, VM lifecycle, ZFS mutation, UPS outlets, battery configuration,
  radio transmission/configuration, and similar infrastructure changes remain read-only unless
  a narrowly documented adapter action is intentionally added.
- Alarm operations must refuse active alarm/fire/trouble state. A configured mandatory bypass
  is confirmed before arming and restored after disarm; sites without that policy do not gain
  one implicitly.
- Read-only tests never invoke actions.

## Apple clients

- iOS builds from `ios/skyHAB.xcworkspace`, not the bare project.
- iOS compiles the repository's exact shared `SkyWireClient.swift`, `DashboardModel.swift`,
  and `PresentationProjections.swift` files.
- MobileVLCKit is deliberately pinned. Upgrade it only after a physical-device RTSP test over
  the intended VPN path.
- Serialize complete SkyWire transactions. Swift actors are reentrant across `await`.
- Detach one-shot Network framework handlers before resuming continuations.

## Verification

```sh
python3 tests/test_inventory.py .
python3 tests/test_presentation.py .
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
swift test --package-path macos
xcodebuild -workspace ios/skyHAB.xcworkspace -scheme skyHAB -sdk iphonesimulator \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
git diff --check
```

Update documentation with architecture, API, schema, security, deployment, or user-visible
changes. Keep speculative work clearly marked as future.
