# Release Process

This repository currently has no checked-in CI workflow. GitLab CI was removed from the public tree, and GitHub Actions have not been added yet.

## Current State

- Releases are manual for now.
- Keep tag naming stable so future GitHub Actions can adopt the same contract.
- Docker registry publishing targets are still undecided; Docker Hub is the baseline and GHCR is a likely future addition.

## Reserved Tag Formats

- Remote + relay images: `remote-v<version>`
- Frontend / npm package: `v<version>` or `v<version>-<timestamp>`

## Manual Flow

1. Update the tracked upstream ref with `scripts/update-vibe-kanban.sh`.
2. Apply and verify the downstream patch stack with `scripts/apply-patches.sh`.
3. Build or publish the artifacts you need manually.
4. Push the release tag you want to preserve for future automation.

## Next Step

Replace the removed GitLab pipeline with GitHub Actions for:
- remote and relay image builds
- optional Docker Hub and GHCR pushes
- npm publishing
- optional GitHub Packages publishing
