# Release Process

This repository uses GitHub Actions for checked-in release automation.

## Current State

- `remote-v*` tags trigger `.github/workflows/release-images.yml`
- `v*` tags trigger `.github/workflows/publish-npm.yml`
- nightly upstream checks run via `.github/workflows/nightly-release-check.yml`
- GHCR is the default public registry for images and the Helm chart
- Docker Hub image pushes are optional and controlled by repository variables and secrets

## Reserved Tag Formats

- Remote + relay images: `remote-v<version>`
- Frontend / npm package: `v<version>` or `v<version>-<timestamp>`

## Remote / Relay Release

Artifacts:
- `ghcr.io/<owner>/vibe-kanban-team-remote:<version>`
- `ghcr.io/<owner>/vibe-kanban-team-relay:<version>`
- `oci://ghcr.io/<owner>/helm-charts/vibe-kanban-team:<version>`

Optional Docker Hub mirrors:
- set `DOCKERHUB_REMOTE_IMAGE_NAME`
- set `DOCKERHUB_RELAY_IMAGE_NAME`
- set `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`

## NPM Release

Artifacts:
- npm package `vibe-kanban-team` published by `scripts/publish-npm.sh`
- binaries uploaded through the existing R2-based publish flow

Required secrets and variables:
- `NPM_TOKEN`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_ENDPOINT`
- `R2_BUCKET`
- `R2_PUBLIC_URL`
- `VITE_PUBLIC_REACT_VIRTUOSO_LICENSE_KEY`

## Manual Flow

1. Update the tracked upstream ref with `scripts/update-vibe-kanban.sh`.
2. Apply and verify the downstream patch stack with `scripts/apply-patches.sh`.
3. Commit and push the submodule or patch changes.
4. Push the release tag for the workflow you want to run.

Manual workflow dispatch is supported for existing release refs only. Pass `git_ref`, let the workflow derive the version from that ref, and avoid free-form version-only publishes.

## Nightly Automation

`nightly-release-check.yml` checks upstream `BloopAI/vibe-kanban` tags for `frontend` and `remote`, verifies downstream patches still apply, updates the tracked submodule ref and patch `From` metadata, then pushes a commit and release tag.

Required secrets:
- `NIGHTLY_RELEASE_PUSH_TOKEN` (PAT or fine-grained token with `contents:write`)
- `DISCORD_WEBHOOK_URL` (used for patch-failure alerts)

## Future Additions

- GHCR image publishing is already included.
- Docker Hub is the public mirror path today.
- GitHub Packages for npm can be added later if you want a secondary registry.
