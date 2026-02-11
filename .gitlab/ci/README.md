# GitLab CI/CD Configuration

This directory contains the GitLab CI/CD pipeline configurations for the Vibe Kanban Cloud repository.

## Tagging Strategy

This repository uses different tag prefixes for different release types:

- **`remote-vX.Y.Z`** or **`remote-X.Y.Z`**: Remote server Docker image releases
  - Examples: `remote-v0.1.2`, `remote-0.1.3`, `remote-v0.1.9-20260210214134`
  - Supports suffixes: `-rc.1`, `-alpha.2`, `-20260210214134`, etc.
  - Triggers: Docker image build, Helm chart packaging

- **`vX.Y.Z`** or **`X.Y.Z`**: NPM package releases (NOT starting with `remote-`)
  - Examples: `v0.1.2`, `0.1.3`, `v0.1.9-20260210214134`
  - Supports suffixes: `-rc.1`, `-alpha.2`, `-20260210214134`, etc.
  - Triggers: NPM package publishing

**Tag Format:** Both patterns follow semver and support optional suffixes after the version:
- Prerelease: `v0.1.9-rc.1`, `v0.1.9-alpha.2`
- Timestamp: `v0.1.9-20260210214134`
- Build metadata: `v0.1.9-rc.1.20260210`

## Pipeline Components

### 1. Image Build (`image-build.yml`)

Builds and publishes Docker images for the Vibe Kanban Remote Server.

**Triggers:**
- On `main` branch when relevant files change:
  - Submodule changes (`vibe-kanban`, `.gitmodules`)
  - Patches (`patches/**/*`, `scripts/apply-patches.sh`)
  - Pipeline configs (`.gitlab/ci/image-build.yml`, `.gitlab-ci.yml`)
- On release tags starting with `remote-` (e.g., `remote-v0.1.2`)

**Outputs:**
- Docker image tagged with commit SHA and `latest` (for main branch)
- Docker image tagged with version for release tags (e.g., `0.1.2` from `remote-v0.1.2`)
- Helm chart packaged and published to GitLab registry

### 2. NPM Publish (`npm-publish.yml`)

Publishes the `@iamriajul/vibe-kanban-fork` NPM package by running `scripts/publish-npm.sh`.

**Triggers:**
- On `main` branch when relevant files change:
  - Submodule changes (`vibe-kanban`, `.gitmodules`)
  - Patches (`patches/**/*`, `scripts/apply-patches.sh`)
  - Publish script (`scripts/publish-npm.sh`)
  - NPM CLI files (`vibe-kanban/npx-cli/**/*`)
  - Pipeline configs (`.gitlab/ci/npm-publish.yml`, `.gitlab-ci.yml`)
- On release tags matching `vX.Y.Z` or `X.Y.Z` pattern (NOT starting with `remote-`)

**Outputs:**
- NPM package published to npm registry
- Binaries uploaded to R2 storage

**Note:** NPM releases use regular version tags (`v0.1.2`), while remote server releases use `remote-` prefixed tags (`remote-v0.1.2`).

## Required CI/CD Variables

Configure these in GitLab under **Settings → CI/CD → Variables**:

### NPM Publishing

These variables are required for the `publish-npm` and `publish-npm-release` jobs:

| Variable | Description | Protected | Masked |
|----------|-------------|-----------|--------|
| `NPM_TOKEN` | npm authentication token for publishing to npm registry | ✅ | ✅ |
| `R2_ACCESS_KEY_ID` | Cloudflare R2 access key ID for binary storage | ✅ | ✅ |
| `R2_SECRET_ACCESS_KEY` | Cloudflare R2 secret access key | ✅ | ✅ |
| `R2_ENDPOINT` | R2 endpoint URL (e.g., `https://xxx.r2.cloudflarestorage.com`) | ✅ | ❌ |
| `R2_BUCKET` | R2 bucket name for storing binaries | ✅ | ❌ |
| `R2_PUBLIC_URL` | Public URL for accessing R2 binaries (e.g., `https://cdn.example.com`) | ✅ | ❌ |
| `VITE_PUBLIC_REACT_VIRTUOSO_LICENSE_KEY` | License key for React Virtuoso | ✅ | ✅ |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NPM_TAG` | npm dist-tag to publish under | `latest` |
| `NPM_VERSION` | Explicit version to publish (auto-detected if not set) | (auto) |
| `DISCORD_WEBHOOK_PRODUCTION` | Discord webhook URL for build notifications | (optional) |
| `FEATURES` | Build features for Docker image | (empty) |
| `POSTHOG_API_KEY` | PostHog API key for analytics | (optional) |
| `POSTHOG_API_ENDPOINT` | PostHog endpoint URL | (optional) |

## Setting Up NPM Token

1. Log in to npm: `npm login`
2. Generate an automation token: `npm token create --type automation`
3. Add the token to GitLab CI/CD variables as `NPM_TOKEN`

## Setting Up R2 Storage

1. Create a Cloudflare R2 bucket
2. Generate R2 API tokens with read/write permissions
3. Set up a custom domain or use the R2 public URL
4. Configure the variables in GitLab

## Pipeline Stages

```
build → release → notify
```

- **build**: Builds Docker images
- **release**: Publishes npm packages and Helm charts (npm jobs run independently, Helm waits for image build)
- **notify**: Sends notifications to Discord

**Note:** NPM publish jobs have `needs: []` which allows them to start immediately without waiting for Docker image builds to complete. This makes npm publishing independent and faster.

## Troubleshooting

### NPM Publish Fails

- Verify `NPM_TOKEN` is valid and has publish permissions
- Check if the version already exists on npm (script will skip if it does)
- Review R2 credentials and permissions
- Ensure all required environment variables are set

### Docker Build Fails

- Check submodule initialization
- Verify patches apply cleanly
- Review build logs for missing dependencies

## Creating Releases

### Remote Server Release

To release a new version of the remote server Docker image:

```bash
# Standard release
git tag remote-v0.1.2
git push origin remote-v0.1.2

# With timestamp suffix
git tag remote-v0.1.9-20260210214134
git push origin remote-v0.1.9-20260210214134

# Release candidate
git tag remote-v0.2.0-rc.1
git push origin remote-v0.2.0-rc.1
```

This will:
1. Build a Docker image tagged as `0.1.2` (or `0.1.9-20260210214134`, etc.)
2. Push to GitLab container registry
3. Package and publish Helm chart with the same version

### NPM Package Release

To release a new version of the npm package:

```bash
# Standard release
git tag v0.1.2
git push origin v0.1.2

# With timestamp suffix
git tag v0.1.9-20260210214134
git push origin v0.1.9-20260210214134

# Release candidate
git tag v0.2.0-rc.1
git push origin v0.2.0-rc.1
```

This will:
1. Build frontend and backend binaries
2. Upload binaries to R2 storage with tag `v0.1.9-20260210214134`
3. Publish npm package `@iamriajul/vibe-kanban-fork@0.1.9-20260210214134`

**Note:** Timestamp-suffixed versions (e.g., `v0.1.9-20260210214134`) are valid semver prerelease versions and will work correctly.

### Combined Release

If you want to release both the remote server and npm package for the same version:

```bash
# Create both tags (with or without timestamp)
git tag remote-v0.1.2
git tag v0.1.2

# Or with timestamp
git tag remote-v0.1.9-20260210214134
git tag v0.1.9-20260210214134

# Push both tags
git push origin --tags
```

## Manual Operations

### Trigger NPM Publish Manually

You can manually run the publish pipeline by:
1. Going to **CI/CD → Pipelines**
2. Click **Run Pipeline**
3. Select the branch (usually `main`)
4. Optionally set variables like `NPM_VERSION=0.1.8`

### Skip Publishing

The npm publish job is marked as `allow_failure: true`, so it won't block the pipeline if it fails. You can manually retry it from the GitLab UI.
