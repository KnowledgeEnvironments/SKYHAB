# Private app bundles

`tools/build_shared_skyhab.sh` places `skyHAB.app` in this directory. Generated app bundles are
ignored by Git.

The public build embeds a loopback endpoint and no token. To build for a private deployment:

```sh
SKYHAB_CLIENT_HOST=host.example.internal \
SKYHAB_CLIENT_PORT=3636 \
SKYHAB_CLIENT_NAME=skyHAB.shared \
tools/build_shared_skyhab.sh
```

`SKYHAB_EMBED_TOKEN_FILE` is an explicit private-deployment escape hatch. When set, the resulting
bundle contains a bearer token and must be protected and distributed as a credential.
