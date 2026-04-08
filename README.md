# Vibe Kanban Team

Open source team deployment and release layer for [Vibe Kanban](https://github.com/BloopAI/vibe-kanban).

`Vibe Kanban Team` is the name of this distribution because the project is centered on shared team environments rather than a single-user local setup. This repo packages the upstream app, the downstream patch stack, the public Helm chart, and the release automation needed to run a collaborative installation.

## Overview

This repository provides a deployment and integration layer for Vibe Kanban with:

- **Helm Chart**: Deploys Vibe Kanban remote server, optional relay server, and ElectricSQL
- **Linear Patch Stack**: One ordered downstream patch series applied to every build
- **Environment-Agnostic Images**: Build once, deploy anywhere
- **External Database**: Bring your own PostgreSQL (CloudNativePG, RDS, etc.)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐    ┌─────────────────┐                     │
│  │                 │    │                 │                     │
│  │  Vibe Kanban    │───▶│   ElectricSQL   │──┐                  │
│  │  Remote Server  │    │   (Sync Layer)  │  │                  │
│  │                 │    │                 │  │                  │
│  │  Port: 8081     │    │  Port: 3000     │  │                  │
│  └────────┬────────┘    └─────────────────┘  │                  │
│           │                                   │                  │
│  ┌────────▼────────┐                         │                  │
│  │     Ingress     │                         │                  │
│  └────────┬────────┘                         │                  │
│           │                                   │                  │
└───────────┼───────────────────────────────────┼──────────────────┘
            │                                   │
            ▼                                   ▼
        Internet                     ┌──────────────────┐
                                     │    PostgreSQL    │
                                     │  (External DB)   │
                                     │  CloudNativePG   │
                                     │  RDS / etc.      │
                                     └──────────────────┘
```

## Prerequisites

- Kubernetes cluster (1.24+)
- Helm 3.x
- PostgreSQL 14+ with `wal_level=logical` (CloudNativePG recommended)
- kubectl configured to access your cluster
- cert-manager installed via the upstream Helm chart (do not use the MicroK8s cert-manager addon)

## cert-manager Installation (Helm, Recommended)

TLS in this chart relies on cert-manager. Install cert-manager using the upstream Helm chart so you stay on a supported release line.

For MicroK8s users, enable core addons without cert-manager:

```bash
microk8s enable dns ingress hostpath-storage community cloudnative-pg
# Intentionally skip: microk8s enable cert-manager
```

Install cert-manager:

```bash
CERT_MANAGER_CHART_VERSION="1.19.4" # update to latest supported patch release

helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version "${CERT_MANAGER_CHART_VERSION}" \
  --set crds.enabled=true

kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s
```

Create a ClusterIssuer (Cloudflare DNS-01 example, supports wildcard relay hosts):

```bash
kubectl -n cert-manager create secret generic cloudflare-dns-api-token \
  --from-literal=API_TOKEN='<cloudflare-api-token>'

kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cert-manager-global
spec:
  acme:
    email: you@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: cert-manager-global-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-dns-api-token
              key: API_TOKEN
EOF
```

Cloudflare token minimum permissions:
- `Zone:Read`
- `DNS:Edit`

## Installation

Clone the public repository and install from the local chart path:

```bash
git clone git@github.com:iamriajul/vibe-kanban-team.git
cd vibe-kanban-team
```

You can then install from the local path `./helm/vibe-kanban-cloud` (see Quick Start below). If you use GitOps (Argo CD / Flux), point your HelmRelease to the `helm/vibe-kanban-cloud` path in this repo.

## Quick Start

### 1. Prepare PostgreSQL Database

Your PostgreSQL must have logical replication enabled:

```sql
-- CloudNativePG has wal_level=logical by default
-- For other providers, ensure wal_level=logical in postgresql.conf

-- Create the electric_sync role for ElectricSQL
CREATE ROLE electric_sync WITH LOGIN PASSWORD 'your-electric-password' REPLICATION;
GRANT ALL PRIVILEGES ON DATABASE your_database TO electric_sync;
```

If you use the CNPG manifests in `k8s/cnpg/`, the `electric_sync` role is created and granted automatically via the init SQL secret. Keep the ElectricSQL password in sync with the value in `k8s/cnpg/02-initdb-secret.yaml`.

### 2. Create Namespace and Kubernetes Secrets

```bash
kubectl create namespace vibe-kanban-cloud

# Database connection URLs
kubectl create secret generic vibe-kanban-db \
  --namespace vibe-kanban-cloud \
  --from-literal=url='postgres://user:pass@your-db-host:5432/remote' \
  --from-literal=electric-url='postgresql://electric_sync:pass@your-db-host:5432/remote?sslmode=disable'

# Application secrets
kubectl create secret generic vibe-kanban-secrets \
  --namespace vibe-kanban-cloud \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=electric-role-password='your-electric-password'

# OAuth credentials
kubectl create secret generic vibe-kanban-oauth \
  --namespace vibe-kanban-cloud \
  --from-literal=github-client-id='your-github-client-id' \
  --from-literal=github-client-secret='your-github-client-secret'
```

### 3. (If Needed) Create Image Pull Secret

If your image registry is private, create a pull secret and reference it in `imagePullSecrets`:

```bash
kubectl create secret docker-registry registry-credentials \
  --namespace vibe-kanban-cloud \
  --docker-server='your-registry.example.com' \
  --docker-username='your-registry-username' \
  --docker-password='your-registry-token' \
  --docker-email='your-email@example.com'
```

### 4. Create Values File

```bash
cp helm/vibe-kanban-cloud/values-example.yaml values-production.yaml
# Edit values-production.yaml with your secret names and image repositories.
```

### 5. Deploy

```bash
helm upgrade --install vibe-kanban ./helm/vibe-kanban-cloud \
  --namespace vibe-kanban-cloud \
  --create-namespace \
  -f values-production.yaml
```

If you want to pin a specific image tag, use:

```bash
scripts/deploy.sh <commit-sha>
```

## Configuration

This chart follows the same pattern as the [Coder Helm chart](https://coder.com/docs/install/kubernetes): reference your own Kubernetes secrets via `secretKeyRef`.

### Example values.yaml

```yaml
env:
  # Database connection (REQUIRED)
  - name: SERVER_DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: vibe-kanban-db
        key: url

  # JWT secret (REQUIRED)
  - name: VIBEKANBAN_REMOTE_JWT_SECRET
    valueFrom:
      secretKeyRef:
        name: vibe-kanban-secrets
        key: jwt-secret

  # ElectricSQL role password (REQUIRED)
  - name: ELECTRIC_ROLE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: vibe-kanban-secrets
        key: electric-role-password

  # GitHub OAuth (REQUIRED - at least one OAuth provider)
  - name: GITHUB_OAUTH_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: vibe-kanban-oauth
        key: github-client-id
  - name: GITHUB_OAUTH_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: vibe-kanban-oauth
        key: github-client-secret

# ElectricSQL database connection
electric:
  enabled: true
  env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: vibe-kanban-db
          key: electric-url
```

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `SERVER_DATABASE_URL` | PostgreSQL connection URL |
| `VIBEKANBAN_REMOTE_JWT_SECRET` | JWT secret (generate with `openssl rand -base64 32`) |
| `ELECTRIC_ROLE_PASSWORD` | Password for the `electric_sync` database role |
| `GITHUB_OAUTH_CLIENT_ID` | GitHub OAuth client ID |
| `GITHUB_OAUTH_CLIENT_SECRET` | GitHub OAuth client secret |

If you're using the CNPG manifests, set `ELECTRIC_ROLE_PASSWORD` to the same value as `CHANGEME_ELECTRIC_PASSWORD` in `k8s/cnpg/02-initdb-secret.yaml`.

### Optional: Relay/Tunnel Deployment

To support tunnel/relay features, enable the `relay` section in values and configure:

- `relay.enabled: true`
- `relay.env` with `SERVER_DATABASE_URL` and `VIBEKANBAN_REMOTE_JWT_SECRET` (same DB/JWT as remote)
- `relay.ingress` with both relay base host and wildcard host (for example `relay.example.com` and `*.relay.example.com`)
- use a DNS-01 capable ClusterIssuer for wildcard relay hosts (for example `cert-manager-global` above)
- keep `relay.proxyUnderRemoteIngress.enabled: true` so relay endpoints are available under the main remote API host (`/v1/relay` and `/relay/h`) for reusable frontend images

`scripts/deploy.sh` now sets both `image.tag` and `relay.image.tag` to the requested release tag.

### Database Requirements

Your PostgreSQL database must have:

1. **Logical replication enabled**: `wal_level=logical`
   - CloudNativePG: Enabled by default
   - Other providers: Set in `postgresql.conf`

2. **ElectricSQL role**: User with `REPLICATION` privilege
   ```sql
   CREATE ROLE electric_sync WITH LOGIN PASSWORD 'xxx' REPLICATION;
   ```

If you use the CNPG manifests, the role is created by the init SQL secret.

### OAuth Setup

#### GitHub OAuth

1. Go to GitHub → Settings → Developer settings → OAuth Apps
2. Create new OAuth App:
   - Homepage URL: `https://your-domain.com`
   - Callback URL: `https://your-domain.com/v1/oauth/callback/github`
3. Copy Client ID and Client Secret

#### Google OAuth

1. Go to Google Cloud Console → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID:
   - Application type: Web application
   - Authorized redirect URIs: `https://your-domain.com/v1/oauth/callback/google`
3. Copy Client ID and Client Secret

## Release Automation

GitHub Actions now handle the checked-in release flows:
- `remote-v*` tags build Remote and Relay images, push to GHCR, optionally mirror to Docker Hub, and publish the Helm chart to GHCR as an OCI artifact
- `v*` tags publish the `vibe-kanban-team` npm package through `scripts/publish-npm.sh`

For stable releases, the image workflow also updates the `latest` tag. Prereleases publish only their version tag.

## Why "Team"

The upstream project is still Vibe Kanban. `Vibe Kanban Team` names this public distribution layer:

- it ships the collaborative deployment shape rather than just the upstream app source
- it keeps a downstream patch stack tuned for shared environments
- it publishes a team-facing npm entrypoint, container images, and a Helm chart under one public name

The goal is to make the “run Vibe Kanban for a team” path obvious and easy to adopt.

## Release Tracking (Upstream Vibe Kanban)

We track upstream releases from the Vibe Kanban GitHub repo and bump the shared `vibe-kanban/` submodule when we want a new feature or fix. Keep it simple:

1. Watch for new upstream releases (GitHub Releases/notifications).
2. Decide the version to adopt (e.g. `v1.4.0`).
3. Update the shared submodule and patch stack.
4. Push the release tag that matches the artifact flow you want.
5. Deploy by pinning the image tag.

## Patch Stack (Downstream Changes)

We keep downstream changes as a small patch stack in `patches/` (similar to quilt). The local scripts and GitHub Actions both apply this same stack before building.

### Creating a Patch

```bash
cd vibe-kanban
git checkout <upstream-tag>
# Make your change(s)
git add .
git commit -m "fix: <summary>"
git format-patch -1 -o ../patches
cd ..
ls patches
```

Rename the patch into the next `NNNN-...patch` slot and add it to `patches/series` in the order you want it applied.

### Applying Patches Locally

```bash
scripts/apply-patches.sh
```

Keep the patch stack minimal and prefer upstreaming when possible.

## Upgrading Vibe Kanban (Process)

```bash
# 1) Update the shared submodule to a tag or commit
scripts/update-vibe-kanban.sh v1.4.0

# 2) Review and commit
git status
git commit -m "chore: bump vibe-kanban to v1.4.0"
git push
```

After merge, CI builds and pushes a new image tagged with the commit SHA.

```bash
# 3) Deploy the new build by pinning the image tag
scripts/deploy.sh <commit-sha>
```

If you want a versioned release tag for this repo (optional), create a tag like `v1.4.0` and push it. CI will also publish a release image tag and a chart package.

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n vibe-kanban-cloud
kubectl describe pod <pod-name> -n vibe-kanban-cloud
```

### View Logs

```bash
# Vibe Kanban server
kubectl logs -n vibe-kanban-cloud -l app.kubernetes.io/name=vibe-kanban-cloud -f

# ElectricSQL
kubectl logs -n vibe-kanban-cloud -l app.kubernetes.io/component=electric -f
```

### ElectricSQL Health

```bash
kubectl port-forward -n vibe-kanban-cloud svc/<release>-electric 3000:3000
curl http://localhost:3000/v1/health
```

## License

This deployment configuration is provided under the MIT License.
Vibe Kanban is licensed under the [BSL License](https://github.com/BloopAI/vibe-kanban/blob/main/LICENSE).
