# Release Process

This document describes the tag-based release workflow for Vibe Kanban Cloud.

## Overview

CI/CD pipelines are **triggered exclusively by Git tags**. There are two distinct release workflows:

1. **Remote Server Deployment** - Docker images and Helm charts
2. **NPM Package Release** - npm CLI package

## Remote Server Releases

**Tag Format:** `remote-v{VERSION}` or `remote-{VERSION}`

**Examples:**
- `remote-v0.1.9`
- `remote-v0.2.0-rc.1`
- `remote-v0.1.9-20260210214134` (with timestamp)

**What Happens:**
1. Docker image is built and pushed to GitLab Registry as `$IMAGE_NAME:{VERSION}`
2. Helm chart is packaged and published to GitLab Helm registry
3. Discord notification is sent (if configured)

**How to Release:**
```bash
# Create and push a remote server release tag
git tag remote-v0.2.0
git push origin remote-v0.2.0
```

**Deployment:**
After the pipeline completes, deploy manually to MicroK8s:
```bash
helm upgrade --install vibe-kanban ./helm/vibe-kanban-cloud \
  --set image.tag=0.2.0 \
  -f values-production.yaml
```

## NPM Package Releases

**Tag Format:** `v{VERSION}` or `{VERSION}` (NOT starting with `remote-`)

**Examples:**
- `v0.1.9`
- `v0.2.0-rc.1`
- `v0.1.9-alpha.2`

**What Happens:**
1. npm package is built and published to npm registry
2. Binaries are uploaded to R2 storage
3. Discord notification is sent (if configured)

**How to Release:**
```bash
# Create and push an npm package release tag
git tag v0.2.0
git push origin v0.2.0
```

## Tag Naming Convention

- **Remote Server:** `remote-v*` or `remote-*`
- **NPM Package:** `v*` or `*` (but NOT `remote-*`)

The prefixes ensure clear separation between release types and prevent accidental dual-triggering.

## Migration Notes

**Previous Behavior (REMOVED):**
- CI/CD previously triggered on pushes to `main` branch with file changes
- This created confusion about when releases would happen

**New Behavior:**
- All releases are **explicit and version-tagged**
- No automatic builds on branch pushes
- Clear audit trail of what was released and when

## Troubleshooting

### Pipeline Not Triggering

Check that your tag matches the expected format:
- Remote server: Must start with `remote-`
- NPM package: Must NOT start with `remote-`
- Both: Must follow semver pattern `X.Y.Z` with optional suffix

### Failed Build

You can manually retry failed jobs in the GitLab CI/CD pipeline interface.

### Discord Notifications

Discord notifications require the `DISCORD_WEBHOOK_PRODUCTION` CI/CD variable to be set. If not configured, notifications are skipped (without failing the pipeline).
