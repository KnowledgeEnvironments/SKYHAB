# opendyson configuration utility

This isolated workspace retrieves Dyson device identity and local MQTT credentials for the
skyHAB middle tier. It is not part of skyhabd and must never run as a permanent bridge.

The local installation pins official `opendyson` release `v0.0.1`. Its universal macOS
archive is verified against the checksum published with that release. `bin/` and `private/`
are ignored by Git; `run.sh` gives the tool a private HOME so account state does not leak into
the normal user profile.

## Log in

From the repository root:

```sh
config-tools/opendyson/run.sh login
```

Follow the prompts for the MyDyson account and complete the verification code sent by Dyson.
Enter credentials only in that local terminal. Do not paste account passwords, OTPs, MQTT
passwords, or the output of `devices` into chat, issues, logs, or Git.

## Capture devices safely

After login:

```sh
config-tools/opendyson/run.sh capture
```

This writes the credential-bearing result with mode 0600 to:

```text
config-tools/opendyson/private/devices.yaml
```

Tell the maintainer only that capture completed. The maintainer can read the local file,
identify models/serials/topics, move required MQTT usernames and passwords into the mode-0600 skyHAB
runtime secret store, and avoid exposing them in output.

## Restore the pinned binary

If `bin/opendyson` is absent, download release `v0.0.1` from the official
`libdyson-wg/opendyson` repository, verify `opendyson_Darwin_all.tar.gz` using
`opendyson_0.0.1_checksums.txt`, and extract `opendyson` plus `LICENSE` into `bin/`.
Do not substitute an unpinned `go install ...@latest` build.
