# Release process

## 1. Verify the candidate

Run the full commands in `AGENTS.md`, build both Apple clients, and exercise the Aurora House demo.
Update `CHANGELOG.md` and `IMPLEMENTATION_STATUS.md`.

## 2. Privacy audit

Follow `docs/PRIVACY.md`. Search tracked files and the exact history that will be pushed for real
addresses, names, coordinates, endpoints, tokens, local paths, and binary artifacts. Inspect every
screenshot manually at full resolution.

The private development history must not be pushed. Export a clean tree, initialize a new Git
history, and create the initial release commit attributed to `if <src@lispm.net>`. Sign it
when a trusted signing identity is configured.

## 3. Version and build

Keep the CMake project version, app bundle versions, changelog, and tag aligned. Build release
artifacts from the clean public checkout so ignored local material cannot enter them.

## 4. Stage privately

Push the clean `master` branch to a **private** `KnowledgeEnvironments/SKYHAB` repository and confirm
CI. Review the complete tree and screenshots from GitHub before changing visibility. Do not make
the repository public until the owner explicitly approves that separate step.

Once approved, create an annotated tag matching the version (for example `v1.1.0`) and a GitHub
release. Source is MIT licensed. If app
binaries are attached, include the corresponding third-party notices and do not embed deployment
tokens or private endpoints.

## 5. Maintain from public master

Keep each real site's inventory, views, secrets, database, and assets external. Product changes go
to the public checkout; deployment changes stay private. Test migrations on copies before pointing
the daemon at a newer binary.
